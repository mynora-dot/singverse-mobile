package com.mynora.singverse.mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Separate from session cookies: signing out keeps explicitly remembered logins. */
internal class LoginVault(context: Context) {
    private val preferences = context.getSharedPreferences("nas-logins", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val alias = "singverse-nas-logins"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    private fun records(): List<JSONObject> {
        val sealed = preferences.getString("sealed", null) ?: return emptyList()
        val parts = sealed.split(':')
        require(parts.size == 2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        val array = JSONArray(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    private fun write(records: List<JSONObject>) {
        val clear = JSONArray(records.take(20)).toString().toByteArray(Charsets.UTF_8)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(cipher.doFinal(clear), Base64.NO_WRAP)
        check(preferences.edit().putString("sealed", sealed).commit())
    }

    private fun matches(record: JSONObject, input: Map<*, *>) =
        record.getString("origin") == NasTransport.normalize(input["origin"] as String) &&
        record.getString("instanceId") == input["instanceId"] && record.getString("username") == input["username"]

    @Synchronized fun list(): String = JSONArray(records().map {
        JSONObject(it.toString()).apply {
            put("hasPassword", optString("password").isNotEmpty()); remove("password")
        }
    }).toString()

    @Synchronized fun password(input: Map<*, *>): String? =
        records().firstOrNull { matches(it, input) }?.optString("password")?.takeIf { it.isNotEmpty() }

    @Synchronized fun save(input: Map<*, *>) {
        val origin = NasTransport.normalize(input["origin"] as String)
        val instance = input["instanceId"] as String
        val username = input["username"] as String
        require(instance.isNotBlank() && instance.length <= 200 && username.isNotBlank() && username.length <= 128)
        val password = input["password"] as? String
        require(password == null || password.length <= 1024)
        val record = JSONObject().put("origin", origin).put("instanceId", instance).put("username", username)
            .put("name", (input["name"] as? String).orEmpty().take(128))
            .put("lastUsed", System.currentTimeMillis())
        if (!password.isNullOrEmpty()) record.put("password", password)
        // Replacing a NAS at the same address must not leave that account's old secret behind.
        write(listOf(record) + records().filterNot { it.getString("origin") == origin && it.getString("username") == username })
    }

    @Synchronized fun remove(input: Map<*, *>) = write(records().filterNot { matches(it, input) })

    @Synchronized fun forgetPassword(input: Map<*, *>) = write(records().onEach {
        if (matches(it, input)) it.remove("password")
    })

    @Synchronized fun forgetServerPasswords(instanceId: String) = write(records().onEach {
        if (it.getString("instanceId") == instanceId) it.remove("password")
    })
}
