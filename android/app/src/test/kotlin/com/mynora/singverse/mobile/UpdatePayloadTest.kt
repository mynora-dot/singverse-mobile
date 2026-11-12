package com.mynora.singverse.mobile

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest

class UpdatePayloadTest {
    private val data = ByteArray(150000) { (it % 251).toByte() }
    private val sha = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
    @Test fun validPayloadStreamsWithoutChangingBytes() {
        val output = ByteArrayOutputStream()
        val progress = mutableListOf<Long>()
        UpdatePayload.copy(ByteArrayInputStream(data), output, data.size.toLong(), sha) { progress.add(it) }
        assertArrayEquals(data, output.toByteArray())
        assertEquals(data.size.toLong(), progress.last())
        assertTrue(progress.size > 2)
    }
    @Test fun wrongLengthOrDigestNeverPasses() {
        for ((size, digest) in listOf(data.size.toLong() - 1 to sha, data.size.toLong() + 1 to sha, data.size.toLong() to "0".repeat(64))) {
            assertThrows(IllegalArgumentException::class.java) {
                UpdatePayload.copy(ByteArrayInputStream(data), ByteArrayOutputStream(), size, digest) { }
            }
        }
    }
    @Test fun cancellationStopsReadingBeforeTheWholePayload() {
        val output = ByteArrayOutputStream()
        assertThrows(IllegalStateException::class.java) {
            UpdatePayload.copy(ByteArrayInputStream(data), output, data.size.toLong(), sha) { if (it > 0) error("cancelled") }
        }
        assertTrue(output.size() < data.size)
    }
    @Test fun cachedFileIsRehashedBeforeEveryInstallationAttempt() {
        val file = File.createTempFile("singverse-update-verification-", ".apk")
        try {
            file.writeBytes(data)
            UpdatePayload.verify(file, data.size.toLong(), sha)
            file.writeBytes(data.copyOf().also { it[100] = (it[100].toInt() xor 1).toByte() })
            assertThrows(IllegalArgumentException::class.java) { UpdatePayload.verify(file, data.size.toLong(), sha) }
            file.writeBytes(data.copyOf(data.size - 1))
            assertThrows(IllegalArgumentException::class.java) { UpdatePayload.verify(file, data.size.toLong(), sha) }
            file.writeBytes(data)
            file.appendBytes(byteArrayOf(1))
            assertThrows(IllegalArgumentException::class.java) { UpdatePayload.verify(file, data.size.toLong(), sha) }
            file.writeBytes(data)
            assertThrows(IllegalStateException::class.java) {
                UpdatePayload.verify(file, data.size.toLong(), sha) { if (it > 0) error("connection changed") }
            }
            UpdatePayload.verify(file, data.size.toLong(), sha)
        } finally { file.delete() }
    }
    @Test fun installationDefersDuringEveryProtectedOperation() {
        for (phase in listOf("TESTING", "RECORDING", "FINALIZING", "RENDERING")) assertTrue(updateBlocked(phase, 0, false))
        assertTrue(updateBlocked("IDLE", 3, false))
        assertTrue(updateBlocked("SAVED", 0, true))
        assertFalse(updateBlocked("PREVIEW", 0, false))
        assertFalse(updateBlocked("IDLE", 0, false))
    }
}
