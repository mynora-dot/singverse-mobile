package com.mynora.singverse.mobile

import org.junit.Assert.*
import org.junit.Test

class DiscoveryAddressTest {
    @Test fun discoveryPreservesProtocolPortAndIpv6Authority() {
        assertEquals("http://192.168.1.8:18080", DiscoveryAddress.origin("192.168.1.8", 18080, "http"))
        assertEquals("https://nas.local:18443", DiscoveryAddress.origin("nas.local", 18443, "https"))
        assertEquals("http://[fd00::1]:18080", DiscoveryAddress.origin("fd00::1", 18080, "http"))
        assertEquals("https://nas.local", DiscoveryAddress.origin("nas.local", 443, "https"))
    }

    @Test fun malformedAdvertisementsNeverBecomeLoginAddresses() {
        for (port in listOf(-1, 0, 65536)) assertNull(DiscoveryAddress.origin("nas.local", port, "http"))
        for (host in listOf("", "user@nas.local", "nas.local/admin", "nas.local?token=x"))
            assertNull(DiscoveryAddress.origin(host, 18080, "http"))
        assertNull(DiscoveryAddress.origin("nas.local", 18080, "file"))
    }
}
