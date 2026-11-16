package com.mynora.singverse.mobile

import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Called on the NAS worker, so prepare/clear and native account changes stay ordered. */
internal class AdminWebSession(
    private val readSession: (String, String?) -> NasAdminSession,
    private val isCurrent: (NasAdminSession) -> Boolean,
    private val writeCookie: (String, String) -> Unit = AndroidAdminCookies::write,
) {
    private var owner: String? = null
    private var origin: String? = null

    fun prepare(id: String, expectedOrigin: String, username: String?) {
        clear()
        val session = readSession(expectedOrigin, username)
        owner = id
        origin = session.connection.origin
        try {
            clearCookies(session.connection.origin)
            session.cookie?.let { writeCookie(session.connection.origin, attributes(session.connection.origin, "singverse_session=$it")) }
            if (!isCurrent(session)) throw NasFailure(409, "App 登录或 NAS 连接已变化，请重新打开管理端")
        } catch (failure: Exception) {
            runCatching { clear(id) }
            throw failure
        }
    }

    fun clear(id: String? = null) {
        if (id != null && owner != id) return
        val previous = origin
        owner = null
        origin = null
        if (previous != null) clearCookies(previous)
    }

    private fun clearCookies(value: String) {
        for (name in listOf("singverse_session", "singverse_challenge", "singverse_csrf")) {
            writeCookie(value, attributes(value, "$name=; Max-Age=0"))
        }
    }

    private fun attributes(origin: String, value: String) =
        "$value; Path=/; HttpOnly; SameSite=Lax${if (URI(origin).scheme == "https") "; Secure" else ""}"
}

/** Cookie values stay native; completion is awaited before WebView loads the admin page. */
private object AndroidAdminCookies {
    private val main = Handler(Looper.getMainLooper())

    fun write(origin: String, cookie: String) {
        val finished = CountDownLatch(1)
        val failure = AtomicReference<Exception?>()
        main.post {
            try {
                CookieManager.getInstance().setCookie(origin, cookie) { accepted ->
                    if (!accepted) failure.set(NasFailure(0, "无法同步管理端登录，请重试"))
                    finished.countDown()
                }
            } catch (error: Exception) {
                failure.set(error)
                finished.countDown()
            }
        }
        if (!finished.await(10, TimeUnit.SECONDS)) throw NasFailure(0, "同步管理端登录超时，请重试")
        failure.get()?.let { throw it }
    }
}
