package com.mynora.singverse.mobile

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class LoginVaultInstrumentedTest {
    @Test fun encryptedHistoryIsScopedToOriginAccountAndNasIdentity() {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val preferenceName = "login-vault-test-${UUID.randomUUID()}"
        val context = object : ContextWrapper(target) {
            override fun getSharedPreferences(name: String, mode: Int) = target.getSharedPreferences(preferenceName, mode)
        }
        val preferences = target.getSharedPreferences(preferenceName, Context.MODE_PRIVATE)
        val input = mapOf("origin" to "http://nas.local:18080", "instanceId" to "nas-a", "username" to "admin", "name" to "客厅曲库")
        val remote = input + ("origin" to "https://remote.example:18443")
        val other = input + ("instanceId" to "nas-b") + ("origin" to "http://other.local:18080")
        try {
            val vault = LoginVault(context)
            vault.save(input + ("password" to "test-only private password")); vault.save(remote + ("password" to "remote-secret"))
            vault.save(other + ("password" to "other-secret"))
            val sealed = preferences.getString("sealed", "")!!
            assertFalse(sealed.contains("nas.local")); assertFalse(sealed.contains("private password")); assertFalse(sealed.contains("admin"))
            val metadata = vault.list()
            assertFalse(metadata.contains("test-only private password")); assertFalse(metadata.contains("\"password\""))
            assertTrue(JSONArray(metadata).getJSONObject(0).getBoolean("hasPassword"))
            assertEquals("test-only private password", LoginVault(context).password(input))
            assertNull(vault.password(input + ("origin" to "https://nas.local:18080")))
            assertNull(vault.password(input + ("instanceId" to "replacement")))
            assertNull(vault.password(input + ("username" to "another-account")))
            vault.forgetPassword(input)
            assertNull(LoginVault(context).password(input)); assertEquals("remote-secret", vault.password(remote))
            vault.forgetServerPasswords("nas-a")
            assertNull(vault.password(remote)); assertEquals("other-secret", vault.password(other))
            vault.remove(other)
            assertNull(vault.password(other)); assertEquals(2, JSONArray(vault.list()).length())
            // Saving metadata without a password also removes a previously saved secret.
            vault.save(input + ("password" to "temporary")); vault.save(input)
            assertNull(LoginVault(context).password(input))
        } finally { preferences.edit().clear().commit() }
    }
}
