package com.mynora.singverse.mobile

import org.junit.Assert.*
import org.junit.Test

class AdminWebSessionTest {
    private val origin = "https://nas.test:18443"
    private val writes = mutableListOf<Pair<String, String>>()
    private var current = true
    private val reads = mutableListOf<Pair<String, String?>>()
    private val sessions = AdminWebSession(
        readSession = { url, username ->
            reads += url to username
            NasAdminSession(NasConnection(url, 1), username?.let { "native-$it" })
        },
        isCurrent = { current },
        writeCookie = { url, cookie -> writes += url to cookie },
    )

    @Test fun currentAccountReplacesAllPreviousAuthenticationCookiesBeforeOpening() {
        sessions.prepare("page-a", origin, "family")
        assertEquals(listOf(origin to "family"), reads)
        assertEquals(4, writes.size)
        assertTrue(writes.take(3).all { it.second.contains("Max-Age=0") })
        val cookie = writes.last().second
        assertEquals("singverse_session=native-family; Path=/; HttpOnly; SameSite=Lax; Secure", cookie)
        assertTrue(writes.all { it.first == origin })
        assertFalse(cookie.contains("Domain="))
        assertFalse(cookie.contains("Max-Age="))
    }

    @Test fun signedOutAppClearsBrowserLoginWithoutCopyingANativeSession() {
        val http = "http://nas.test:18080"
        sessions.prepare("page-a", http, null)
        assertEquals(listOf(http to null), reads)
        assertEquals(3, writes.size)
        assertTrue(writes.all { it.second.contains("Max-Age=0") && !it.second.contains("Secure") })
    }

    @Test fun closingAnOldPageCannotClearTheNewAccount() {
        sessions.prepare("page-a", origin, "admin")
        sessions.prepare("page-b", origin, "family")
        val before = writes.toList()
        sessions.clear("page-a")
        assertEquals(before, writes)
        sessions.clear("page-b")
        assertEquals(before.size + 3, writes.size)
        assertTrue(writes.takeLast(3).all { it.second.contains("Max-Age=0") })
    }

    @Test fun changedNativeSessionIsRemovedAndNeverReportedReady() {
        current = false
        try {
            sessions.prepare("page-a", origin, "admin")
            fail("changed native session must not open admin")
        } catch (failure: NasFailure) { assertEquals(409, failure.status) }
        assertTrue(writes.takeLast(3).all { it.second.contains("Max-Age=0") })
    }

    @Test fun changingNasClearsThePreviousHostBeforePreparingTheNextHost() {
        sessions.prepare("page-a", origin, "admin")
        writes.clear()
        val next = "http://other-nas.test:18080"
        sessions.prepare("page-b", next, "family")
        assertTrue(writes.take(3).all { it.first == origin && it.second.contains("Max-Age=0") })
        assertTrue(writes.drop(3).all { it.first == next })
        sessions.clear()
        assertTrue(writes.takeLast(3).all { it.first == next && it.second.contains("Max-Age=0") })
    }
}
