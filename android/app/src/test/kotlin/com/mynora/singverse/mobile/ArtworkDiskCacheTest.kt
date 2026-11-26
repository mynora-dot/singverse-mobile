package com.mynora.singverse.mobile

import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile

class ArtworkDiskCacheTest {
    @get:Rule val temporary = TemporaryFolder()

    private val artwork = "/api/v1/metadata/songs/song/cover"
    private val origin = "http://nas:18080"
    private val etag = "\"ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb\""

    private fun key(path: String = artwork, revision: String = "r1", instance: String = "nas-id", account: String = "owner") =
        requireNotNull(artworkCacheKey(origin, instance, account, path, revision))

    @Test fun diskNamespacesAndRoutesAreExplicit() {
        assertNotEquals(key(), key(account = "shared"))
        assertNotEquals(key(), key(instance = "replacement-nas"))
        assertNotEquals(key(), key(revision = "r2"))
        assertNotEquals(key(), key(path = "$artwork?variant=thumbnail"))
        assertNull(artworkCacheKey(origin, "id", "owner", "$artwork?token=secret", null))
        assertNull(artworkCacheKey(origin, "id", "owner", "/api/v1/metadata/assets/preview", null))
    }

    @Test fun privateGrantIsRequiredEvenOnNotModified() {
        fun response(control: String, tag: String = etag) = Response.Builder()
            .request(Request.Builder().url(origin + artwork).build()).protocol(Protocol.HTTP_1_1)
            .message("Not Modified").code(304).header("Cache-Control", control).header("ETag", tag)
            .header("Vary", "Authorization, Cookie").build()
        assertEquals(etag to 301_000L, artworkGrant(response("private, max-age=300"), 1_000L))
        assertNull(artworkGrant(response("private, no-store, max-age=300"), 1_000L))
        assertNull(artworkGrant(response("public, max-age=300"), 1_000L))
        assertNull(artworkGrant(response("private, max-age=300", "W/$etag"), 1_000L))
    }

    @Test fun persistentEntriesHonorExpiryAndRejectSameLengthCorruption() {
        val directory = temporary.newFolder()
        val cache = ArtworkDiskCache(directory)
        val bytes = "a".toByteArray()
        val entry = StoredArtwork(etag, ArtworkPayload(bytes, 301_000L))
        cache.write(key(), entry, 1_000L) { it() }

        val reopened = ArtworkDiskCache(directory)
        assertArrayEquals(bytes, reopened.read(key(), 2_000L)!!.payload.bytes)
        assertTrue(reopened.read(key(), 300_999L)!!.freshAt(300_999L))
        assertFalse(reopened.read(key(), 301_000L)!!.freshAt(301_000L))
        val file = File(directory, key())
        RandomAccessFile(file, "rw").use { handle -> handle.seek(handle.length() - 1); handle.write('b'.code) }
        assertNull(reopened.read(key(), 301_001L))
        assertFalse(file.exists())
    }

    @Test fun budgetEvictsOlderEntriesAndCanceledWriteLeavesNoEntry() {
        val cache = ArtworkDiskCache(temporary.newFolder(), maxBytes = 100L)
        val entry = StoredArtwork(etag, ArtworkPayload("a".toByteArray(), 301_000L))
        cache.write(key(revision = "cancelled"), entry, 1_000L) { }
        assertNull(cache.read(key(revision = "cancelled"), 1_100L))
        cache.write(key(), entry, 2_000L) { it() }
        cache.write(key(revision = "r2"), entry, 3_000L) { it() }
        assertNull(cache.read(key(), 3_100L))
        assertNotNull(cache.read(key(revision = "r2"), 3_100L))
    }
}
