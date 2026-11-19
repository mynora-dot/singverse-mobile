package com.mynora.singverse.mobile

internal object UpdateAbi {
    private val known = setOf("armeabi-v7a", "arm64-v8a", "x86_64")

    fun preferred(supported: List<String>, declared: List<String>? = null): String? =
        supported.firstOrNull { it in known && (declared == null || "universal" in declared || it in declared) }
}
