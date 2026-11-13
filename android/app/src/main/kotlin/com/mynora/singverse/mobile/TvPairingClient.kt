package com.mynora.singverse.mobile

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.net.Proxy
import java.util.concurrent.TimeUnit

/** Credentials stay in the native bridge; Flutter receives only device labels and outcomes. */
internal class TvPairingClient(private val transport: NasTransport) {
    private val http = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).proxy(Proxy.NO_PROXY)
        .connectTimeout(5, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).build()
    private class Pending(val code: TvPairingCode, val connection: NasConnection) {
        val id = TvPairingProtocol.randomHex(16)
        val scope = NasRequestScope(35_000)
        var name = "电视"
        var deadline = 0L
        var confirming = false
        var deviceId = ""
        var completed = false
    }
    private var pending: Pending? = null

    fun inspect(raw: String, expectedOrigin: String): Map<String, Any> {
        val code = try { TvPairingCode.parse(raw) } catch (_: Exception) { throw NasFailure(400, "请扫描同一网络内的 SingVerse 电视登录码") }
        val connection = transport.connectionIdentity()
        if (connection.origin.isBlank() || connection.origin != expectedOrigin) throw NasFailure(409, "音乐库已切换，请重新扫码")
        val active = Pending(code, connection)
        synchronized(this) { cancel(); pending = active }
        try {
            // Recheck the authenticated session, including MFA, before presenting a confirmation.
            transport.scopedRequest(connection, "/api/v1/auth/session", "GET", null, active.scope)
            val info = exchange(active, "inspect", JSONObject())
            checkCurrent(active)
            val remaining = info.getInt("remainingSeconds")
            if (remaining !in 1..300 || info.getString("state") !in listOf("waiting", "scanned")) throw NasFailure(409, "电视登录码已使用或过期，请刷新后扫码")
            active.name = info.getString("name").take(60).filter { !it.isISOControl() }.ifBlank { "SingVerse TV" }
            active.deadline = System.nanoTime() + remaining * 1_000_000_000L
            return mapOf("id" to active.id, "name" to active.name, "remainingSeconds" to remaining)
        } catch (failure: Exception) {
            synchronized(this) { if (pending === active) cancel() }
            throw failure
        }
    }

    fun confirm(id: String, expectedOrigin: String) {
        val active = synchronized(this) {
            val current = pending ?: throw NasFailure(409, "请重新扫描电视登录码")
            if (current.id != id || current.confirming || current.connection.origin != expectedOrigin) throw NasFailure(409, "登录已变化，请重新扫码")
            current.confirming = true
            current
        }
        try {
            checkCurrent(active)
            if (System.nanoTime() >= active.deadline) throw NasFailure(410, "二维码已过期，请刷新后扫码")
            // Reuse the existing account-login exchange; no authorization request or approval API.
            val credential = JSONObject(transport.scopedRequest(active.connection, "/api/v1/auth/tv-session", "POST",
                JSONObject().put("name", active.name).toString(), active.scope))
            active.deviceId = credential.getString("deviceId")
            val token = credential.getString("token")
            require(active.deviceId.matches(Regex("[A-Za-z0-9_-]{1,100}")) && token.matches(Regex("[A-Za-z0-9_-]{40,200}")))
            checkCurrent(active)
            val body = JSONObject().put("origin", active.connection.origin).put("token", token)
            val result = try { exchange(active, "connect", body) } catch (failure: Exception) {
                // A lost reply must not blindly create a second TV login.
                checkCurrent(active)
                try { exchange(active, "inspect", JSONObject()) } catch (_: Exception) { throw failure }
            }
            checkCurrent(active)
            if (result.getString("state") != "connected") throw NasFailure(409, result.optString("message").ifBlank { "电视尚未完成连接，请查看电视屏幕并重试" })
            active.completed = true
        } finally {
            if (!active.completed && active.deviceId.isNotBlank()) {
                // On cancellation/failure, dispose only this attempt's freshly issued credential.
                runCatching { transport.scopedRequest(active.connection, "/api/v1/admin/tv-devices/${active.deviceId}", "DELETE", null, NasRequestScope(5000)) }
            }
            synchronized(this) { if (pending === active) pending = null }
            active.scope.cancel(); active.code.key.fill(0)
        }
    }

    @Synchronized private fun checkCurrent(active: Pending) {
        if (pending !== active || active.scope.cancelled || transport.connectionIdentity() != active.connection) throw NasFailure(409, "本次登录已取消或音乐库已切换，请重新扫码")
    }

    private fun exchange(active: Pending, action: String, value: JSONObject): JSONObject {
        checkCurrent(active)
        value.put("requestId", active.id)
        val sealed = TvPairingProtocol.seal(active.code.key, active.code.session, "$action-request", value.toString().toByteArray(Charsets.UTF_8))
        val body = JSONObject().put("nonce", sealed.first).put("ciphertext", sealed.second).toString()
        val call = http.newCall(Request.Builder().url("${active.code.endpoint}/pair/v1/${active.code.session}/$action")
            .post(body.toRequestBody("application/json; charset=utf-8".toMediaType())).header("Accept", "application/json").build())
        active.scope.attach(call)
        try {
            return call.execute().use { response ->
                if (response.code != 200) throw NasFailure(response.code, "二维码已失效，请刷新电视二维码重试")
                val source = response.body?.byteStream() ?: throw NasFailure(502, "电视未返回登录状态")
                val output = java.io.ByteArrayOutputStream()
                val chunk = ByteArray(1024)
                source.use { while (true) { val count = it.read(chunk); if (count < 0) break; if (output.size() + count > 8192) throw NasFailure(502, "电视响应无效"); output.write(chunk, 0, count) } }
                val envelope = JSONObject(output.toString("UTF-8"))
                val clear = JSONObject(TvPairingProtocol.open(active.code.key, active.code.session, "$action-response", envelope.getString("nonce"), envelope.getString("ciphertext")).toString(Charsets.UTF_8))
                if (clear.getString("requestId") != active.id) throw NasFailure(409, "电视登录状态已变化，请重新扫码")
                clear
            }
        } catch (failure: NasFailure) { throw failure }
        catch (_: Exception) { throw NasFailure(0, "无法连接电视，请确认手机与电视在同一网络，并刷新二维码重试") }
        finally { active.scope.detach(call) }
    }

    @Synchronized fun cancel(id: String? = null) {
        val current = pending ?: return
        if (id != null && id != current.id) return
        pending = null
        current.scope.cancel()
        if (!current.confirming) current.code.key.fill(0)
    }
}
