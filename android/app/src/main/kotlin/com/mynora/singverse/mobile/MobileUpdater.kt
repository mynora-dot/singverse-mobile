package com.mynora.singverse.mobile

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import okhttp3.Call
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile
import java.util.concurrent.Executor

/** Downloads remain bound to the active household NAS and never follow redirects. */
internal class MobileUpdater(
    private val activity: Activity,
    private val transport: NasTransport,
    private val worker: Executor,
    private val busy: () -> Boolean,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val lock = Any()
    private var generation = 0L
    private var call: Call? = null
    private var ready: File? = null
    private var release: JSONObject? = null
    private var connection: NasConnection? = null
    @Volatile private var permissionPending = false
    private val directory = File(activity.cacheDir, "updates").apply { mkdirs() }

    init { directory.listFiles()?.filter { it.isFile }?.forEach { it.delete() } }

    @Suppress("DEPRECATION")
    private fun flags() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    @Suppress("DEPRECATION")
    private fun version(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        require(!signatures.isNullOrEmpty()) { "无法读取应用签名" }
        return signatures.map { sha256(it.toByteArray()) }.toSet()
    }
    private fun installed(): PackageInfo = activity.packageManager.getPackageInfo(activity.packageName, flags())
    fun info(): Map<String, Any?> {
        val value = installed()
        return mapOf("packageName" to value.packageName, "versionCode" to version(value),
            "versionName" to value.versionName, "sdk" to Build.VERSION.SDK_INT,
            "abis" to Build.SUPPORTED_ABIS.toList(), "certificateSha256" to certificates(value).single())
    }
    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun check(ticket: Long, server: NasConnection) {
        require(synchronized(lock) { generation == ticket } && transport.connectionIdentity() == server) { "下载已取消或 NAS 连接已切换" }
    }
    fun cancel() {
        synchronized(lock) {
            generation++
            call?.cancel()
            call = null
            ready?.delete()
            ready = null
            release = null
            connection = null
            permissionPending = false
        }
    }
    fun reserveDownload(): Pair<Long, NasConnection> {
        cancel()
        return synchronized(lock) { generation to transport.connectionIdentity() }
    }
    fun download(manifest: JSONObject, reservation: Pair<Long, NasConnection>) {
        val (ticket, server) = reservation
        check(ticket, server)
        require(server.origin.isNotBlank()) { "请先连接家庭 NAS" }
        require(manifest.getString("url") == "/api/v1/client-releases/mobile/apk") { "安装包地址无效" }
        val size = manifest.getLong("size")
        require(size in 1..268435456) { "安装包大小无效" }
        val expectedHash = manifest.getString("sha256")
        require(Regex("[a-f0-9]{64}").matches(expectedHash)) { "安装包摘要无效" }
        val local = installed()
        require(manifest.getString("packageName") == activity.packageName && manifest.getLong("versionCode") > version(local)) { "安装包不是更新版本" }
        require(manifest.getInt("minSdk") <= Build.VERSION.SDK_INT) { "新版本不支持此 Android 版本" }
        require(manifest.getString("certificateSha256") in certificates(local)) { "新版本签名与当前应用不同" }
        val supported = manifest.getJSONArray("abis").let { values -> (0 until values.length()).map { values.getString(it) } }
        require(supported.isEmpty() || "universal" in supported || supported.any { it in Build.SUPPORTED_ABIS }) { "新版本不支持此手机处理器" }
        val temporary = File(directory, "download-$ticket.part")
        val file = File(directory, "singverse-mobile-$ticket.apk")
        require(directory.usableSpace > size + 10485760) { "手机存储空间不足" }
        val request = Request.Builder().url(server.origin + manifest.getString("url")).build()
        val download = transport.mediaClient().newCall(request)
        synchronized(lock) { check(ticket, server); call = download }
        try {
            download.execute().use { response ->
                require(response.code == 200) { "无法读取安装包，请检查 NAS 连接" }
                var lastProgress = 0L
                response.body?.byteStream()?.use { input -> temporary.outputStream().use { output ->
                    UpdatePayload.copy(input, output, size, expectedHash) { length ->
                        check(ticket, server)
                        val now = android.os.SystemClock.elapsedRealtime()
                        if (now - lastProgress > 150 || length == size) {
                            emit(mapOf("origin" to server.origin, "requestGeneration" to manifest.getLong("requestGeneration"), "received" to length))
                            lastProgress = now
                        }
                    }
                } } ?: error("安装包内容为空")
            }
            check(ticket, server)
            verify(temporary, manifest)
            synchronized(lock) {
                check(ticket, server)
                require(temporary.renameTo(file)) { "无法保存已校验安装包" }
                ready = file
                release = manifest
                connection = server
                call = null
            }
        } catch (e: Exception) {
            temporary.delete()
            file.delete()
            throw e
        } finally {
            synchronized(lock) { if (call === download) call = null }
        }
    }
    private fun verify(file: File, manifest: JSONObject, current: () -> Unit = {}) {
        UpdatePayload.verify(file, manifest.getLong("size"), manifest.getString("sha256")) { current() }
        val archive = activity.packageManager.getPackageArchiveInfo(file.absolutePath, flags()) ?: error("安装包格式无效")
        val local = installed()
        require(archive.packageName == activity.packageName && archive.packageName == manifest.getString("packageName")) { "安装包包名不匹配" }
        require(version(archive) == manifest.getLong("versionCode") && version(archive) > version(local) && archive.versionName == manifest.getString("versionName")) { "安装包版本不匹配或不是更新版本" }
        require(archive.applicationInfo?.minSdkVersion == manifest.getInt("minSdk") && manifest.getInt("minSdk") <= Build.VERSION.SDK_INT) { "安装包 Android 版本要求不匹配" }
        val signers = certificates(archive)
        require(signers == certificates(local) && signers.single() == manifest.getString("certificateSha256")) { "安装包签名与当前应用不同，拒绝安装" }
        val actualAbis = ZipFile(file).use { zip -> zip.entries().asSequence().map { it.name }.filter { it.startsWith("lib/") && it.endsWith(".so") }.map { it.split('/')[1] }.toSet() }
        val declared = manifest.getJSONArray("abis").let { values -> (0 until values.length()).map { values.getString(it) }.toSet() }
        require((if (actualAbis.isEmpty()) setOf("universal") else actualAbis) == declared && (actualAbis.isEmpty() || actualAbis.any { it in Build.SUPPORTED_ABIS })) { "安装包处理器架构不匹配" }
    }
    private data class Installation(val ticket: Long, val server: NasConnection, val file: File, val manifest: JSONObject)
    private fun requestPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()) return false
        permissionPending = true
        @Suppress("DEPRECATION")
        activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")), 7405)
        return true
    }
    fun install(complete: (Result<String>) -> Unit) {
        try {
            val pending = synchronized(lock) {
                Installation(generation, connection ?: error("请先下载更新"), ready ?: error("请先下载更新"), release ?: error("请先下载更新"))
            }
            check(pending.ticket, pending.server)
            require(pending.file.isFile) { "安装包已变化，请重新下载" }
            if (busy()) { complete(Result.success("deferred")); return }
            if (requestPermission()) { complete(Result.success("permission")); return }
            // APK hashing/parsing never blocks the UI; permission returns use this same path.
            worker.execute {
                val verified = runCatching {
                    check(pending.ticket, pending.server)
                    verify(pending.file, pending.manifest) { check(pending.ticket, pending.server) }
                }
                if (verified.isFailure) synchronized(lock) {
                    if (generation == pending.ticket && ready == pending.file) {
                        pending.file.delete()
                        ready = null
                        release = null
                        connection = null
                        permissionPending = false
                    }
                }
                activity.runOnUiThread {
                    complete(verified.mapCatching {
                        check(pending.ticket, pending.server)
                        require(pending.file.isFile) { "安装包已变化，请重新下载" }
                        if (busy()) return@mapCatching "deferred"
                        if (requestPermission()) return@mapCatching "permission"
                        permissionPending = false
                        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".updates", pending.file)
                        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        emit(mapOf("origin" to pending.server.origin, "requestGeneration" to pending.manifest.getLong("requestGeneration"), "status" to "installer"))
                        "installer"
                    })
                }
            }
        } catch (e: Exception) { complete(Result.failure(e)) }
    }
    fun resumeInstallation() {
        if (!permissionPending) return
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) { permissionPending = false; return }
        val request = synchronized(lock) { release?.optLong("requestGeneration") }
        val server = transport.origin
        install { outcome ->
            outcome.onSuccess { result ->
                if (result == "deferred") emit(mapOf("origin" to transport.origin, "requestGeneration" to synchronized(lock) { release?.optLong("requestGeneration") }, "status" to result))
            }.onFailure { error ->
                permissionPending = false
                emit(mapOf("origin" to server, "requestGeneration" to request, "status" to "invalid", "message" to (error.message ?: "安装包校验失败，请重新下载")))
            }
        }
    }
}
