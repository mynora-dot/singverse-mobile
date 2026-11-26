package com.mynora.singverse.mobile

import okhttp3.Response
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import java.security.MessageDigest

internal const val ARTWORK_MAX_BYTES = 8 * 1024 * 1024
internal const val ARTWORK_MAX_AGE_MS = 300_000L

internal data class ArtworkPayload(val bytes: ByteArray, val expiresAt: Long)

internal data class StoredArtwork(val etag: String, val payload: ArtworkPayload) {
    fun freshAt(now: Long): Boolean = payload.expiresAt - now in 1..ARTWORK_MAX_AGE_MS
}

internal class ArtworkDiskCache(
    private val directory: File,
    private val maxBytes: Long = 128L * 1024 * 1024,
    private val maxEntries: Int = 2048,
) {
    fun read(key: String, now: Long): StoredArtwork? = synchronized(diskLock) {
        val file = File(directory, key)
        try {
            DataInputStream(file.inputStream().buffered()).use { input ->
                val fileSize = file.length()
                if (fileSize !in 1..(ARTWORK_MAX_BYTES + 128L)) throw IOException()
                val etag = input.readUTF()
                val expiresAt = input.readLong()
                val size = input.readInt()
                if (!validArtworkEtag(etag) || size !in 1..ARTWORK_MAX_BYTES || size >= fileSize) throw IOException()
                val bytes = ByteArray(size)
                input.readFully(bytes)
                if (input.read() != -1 || !artworkMatchesEtag(bytes, etag)) throw IOException()
                file.setLastModified(now)
                StoredArtwork(etag, ArtworkPayload(bytes, expiresAt))
            }
        } catch (_: IOException) {
            file.delete()
            null
        }
    }

    fun write(key: String, entry: StoredArtwork, now: Long, commit: (() -> Unit) -> Unit) = synchronized(diskLock) {
        if (entry.payload.bytes.size !in 1..ARTWORK_MAX_BYTES || entry.payload.bytes.size >= maxBytes) return@synchronized
        val temp = try {
            directory.mkdirs()
            File.createTempFile("artwork-", ".tmp", directory)
        } catch (_: IOException) { return@synchronized }

        try {
            DataOutputStream(temp.outputStream().buffered()).use { output ->
                output.writeUTF(entry.etag)
                output.writeLong(entry.payload.expiresAt)
                output.writeInt(entry.payload.bytes.size)
                output.write(entry.payload.bytes)
            }
            val file = File(directory, key)
            temp.setLastModified(now)
            if (temp.length() > maxBytes) return@synchronized
            var published = false
            commit { published = temp.renameTo(file) }
            if (published) trim()
        } catch (_: IOException) {
            // Storage can be reclaimed independently of successful artwork requests.
        } finally {
            temp.delete()
        }
    }

    fun remove(key: String, commit: (() -> Unit) -> Unit) = synchronized(diskLock) {
        commit { File(directory, key).delete() }
    }

    private fun trim() {
        val files = directory.listFiles() ?: return
        val entries = files.filter { it.name.endsWith(".art") }
        var bytes = entries.sumOf { it.length() }
        var count = entries.size
        for (file in entries.sortedBy { it.lastModified() }) {
            if (bytes <= maxBytes && count <= maxEntries) break
            val size = file.length()
            if (file.delete()) {
                bytes -= size
                count--
            }
        }
        files.filter { it.name.endsWith(".tmp") }.forEach { it.delete() }
    }

    private companion object {
        val diskLock = Any()
    }
}

private val artworkPath = Regex("/api/v1/(metadata/songs/[^/]+/cover|artists/[^/]+/images/(portrait|background)|classification/tags/[^/]+/cover)")
private val artworkETag = Regex("\"[0-9a-f]{64}\"")

private fun validArtworkEtag(value: String): Boolean = artworkETag.matches(value)
private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }

internal fun artworkMatchesEtag(bytes: ByteArray, etag: String): Boolean =
    etag == "\"${MessageDigest.getInstance("SHA-256").digest(bytes).hex()}\""

internal fun artworkCacheKey(origin: String, instance: String, account: String, path: String, revision: String?): String? {
    val resource = path.substringBefore('?')
    if (!artworkPath.matches(resource) || resource.contains('#') || instance.isBlank() || account.isBlank()) return null
    if (path != resource && (path != "$resource?variant=thumbnail" || !resource.startsWith("/api/v1/metadata/songs/"))) return null
    val digest = MessageDigest.getInstance("SHA-256")
    for (field in listOf(origin, instance, account, path, revision.orEmpty())) {
        digest.update("${field.length}:$field".toByteArray(Charsets.UTF_8))
    }
    return digest.digest().hex() + ".art"
}

internal fun artworkGrant(response: Response, now: Long): Pair<String, Long>? {
    val control = response.cacheControl
    val etag = response.header("ETag") ?: return null
    if (!control.isPrivate || control.isPublic || control.noStore || control.noCache ||
        control.maxAgeSeconds != 300 || !validArtworkEtag(etag) || response.headers("Vary").any { "*" in it }) return null
    val age = response.header("Age")?.toLongOrNull()?.coerceIn(0, 300) ?: 0
    return etag to now + ARTWORK_MAX_AGE_MS - age * 1000
}
