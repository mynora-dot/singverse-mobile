package com.mynora.singverse.mobile

import org.junit.Assert.*
import org.junit.Test

class UpdateAbiTest {
    @Test fun devicePreferenceChoosesArm64AndKeepsArm32AndX8664DevicesSupported() {
        assertEquals("arm64-v8a", UpdateAbi.preferred(listOf("arm64-v8a", "armeabi-v7a")))
        assertEquals("armeabi-v7a", UpdateAbi.preferred(listOf("armeabi-v7a")))
        assertEquals("x86_64", UpdateAbi.preferred(listOf("x86_64", "x86")))
        assertNull(UpdateAbi.preferred(listOf("unsupported")))
    }

    @Test fun downloadPinsTheMetadataAbiRatherThanSwitchingBackToTheDeviceDefault() {
        val device = listOf("arm64-v8a", "armeabi-v7a")
        assertEquals("armeabi-v7a", UpdateAbi.preferred(device, listOf("armeabi-v7a")))
        assertEquals("arm64-v8a", UpdateAbi.preferred(device, listOf("universal")))
        assertNull(UpdateAbi.preferred(device, listOf("x86_64")))
    }
}
