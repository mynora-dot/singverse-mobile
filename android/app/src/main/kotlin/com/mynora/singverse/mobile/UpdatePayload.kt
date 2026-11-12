package com.mynora.singverse.mobile

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

internal object UpdatePayload {
    fun verify(file: File, size: Long, sha256: String, progress: (Long) -> Unit = {}) {
        require(file.isFile && file.length() == size) { "安装包大小已变化，请重新下载" }
        val discard = object : OutputStream() {
            override fun write(value: Int) {}
            override fun write(bytes: ByteArray, offset: Int, length: Int) {}
        }
        file.inputStream().use { copy(it, discard, size, sha256, progress) }
    }
    fun copy(input: InputStream, output: OutputStream, size: Long, sha256: String, progress: (Long) -> Unit) {
        require(size in 1..268435456 && Regex("[a-f0-9]{64}").matches(sha256)) { "安装包信息无效" }
        val hash = MessageDigest.getInstance("SHA-256")
        var length = 0L
        val bytes = ByteArray(65536)
        while (true) {
            progress(length)
            val n = input.read(bytes)
            if (n < 0) break
            length += n
            require(length <= size) { "安装包大小异常" }
            output.write(bytes, 0, n)
            hash.update(bytes, 0, n)
        }
        require(length == size && hash.digest().joinToString("") { "%02x".format(it) } == sha256) { "安装包大小或 SHA-256 校验失败" }
        progress(length)
    }
}

internal fun updateBlocked(phase: String, countdown: Int, exporting: Boolean): Boolean =
    exporting || countdown > 0 || phase in setOf("TESTING", "RECORDING", "FINALIZING", "RENDERING")
