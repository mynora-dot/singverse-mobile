package com.mynora.singverse.mobile

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import java.net.URI

internal object DiscoveryAddress {
    fun origin(host: String, port: Int, scheme: String): String? {
        if (scheme !in listOf("http", "https") || port !in 1..65535 || host.isBlank()) return null
        return runCatching { NasTransport.normalize(URI(scheme, null, host, port, null, null, null).toString()) }.getOrNull()
    }
}

/** DNS-SD only; selection still requires server-info verification before login. */
internal class NasDiscovery(context: Context, private val emit: (Map<String, Any?>) -> Unit) {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val main = Handler(Looper.getMainLooper())
    private var listener: NsdManager.DiscoveryListener? = null
    private var generation = 0
    private var resolving = false
    private val pending = java.util.ArrayDeque<NsdServiceInfo>()
    private val available = mutableSetOf<String>()
    private val services = linkedMapOf<String, Map<String, String>>()
    private var error: String? = null
    private var timeout: Runnable? = null

    fun snapshot() = emit(mapOf("searching" to (listener != null), "error" to error,
        "services" to services.values.distinctBy { it["origin"] }.toList()))

    @Suppress("DEPRECATION") private fun resolve() {
        if (resolving || pending.isEmpty() || listener == null) return
        resolving = true
        val epoch = generation
        val candidate = pending.removeFirst()
        fun complete(info: NsdServiceInfo?) {
            main.post {
                resolving = false
                if (epoch == generation && listener != null && candidate.serviceName in available && info != null) {
                    val scheme = info.attributes["scheme"]?.toString(Charsets.UTF_8) ?: "http"
                    val origin = info.host?.hostAddress?.let { DiscoveryAddress.origin(it, info.port, scheme) }
                    if (origin != null && services.size < 20) {
                        services[candidate.serviceName] = mapOf("name" to info.serviceName, "origin" to origin)
                        snapshot()
                    }
                }
                resolve()
            }
        }
        runCatching {
            manager.resolveService(candidate, object : NsdManager.ResolveListener {
                override fun onResolveFailed(info: NsdServiceInfo, code: Int) = complete(null)
                override fun onServiceResolved(info: NsdServiceInfo) = complete(info)
            })
        }.onFailure { complete(null) }
    }

    fun start() {
        stop(); services.clear(); error = null
        val next = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) { main.post { if (listener === this) snapshot() } }
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) {
                main.post { if (listener === this) { error = "无法查找局域网设备，请检查网络后重试"; stop() } }
            }
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) {
                main.post {
                    if (listener === this && available.size < 40 && available.add(info.serviceName)) {
                        pending.add(info); resolve()
                    }
                }
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                main.post {
                    if (listener === this) {
                        available.remove(info.serviceName)
                        pending.removeAll { it.serviceName == info.serviceName }
                        services.remove(info.serviceName); snapshot()
                    }
                }
            }
        }
        listener = next
        runCatching { manager.discoverServices("_singverse._tcp.", NsdManager.PROTOCOL_DNS_SD, next) }
            .onFailure { error = "无法查找局域网设备，请检查网络后重试"; stop() }
        if (listener === next) {
            timeout = Runnable { if (listener === next) stop() }.also { main.postDelayed(it, 15000) }
        }
        snapshot()
    }

    fun stop() {
        generation++
        timeout?.let { main.removeCallbacks(it) }; timeout = null
        val old = listener; listener = null; pending.clear(); available.clear()
        old?.let { runCatching { manager.stopServiceDiscovery(it) } }
        snapshot()
    }
}
