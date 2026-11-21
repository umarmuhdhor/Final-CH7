package com.shoo.app.data

import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * One secret string (SECURITY §3 P4, T3). iOS: a generic-password Keychain item, `AfterFirstUnlockThisDeviceOnly`.
 * An interface so tests and previews use [InMemoryKeychainItem].
 */
interface KeychainItem {
    /** null only when there is no item (or it can never be read again). A store that can't be opened right now throws,
     * so it is never mistaken for a lost session. */
    fun read(): String?

    fun write(value: String)

    fun delete()
}

/**
 * Android: AES-GCM with a key in the Android Keystore that never leaves the phone and is never backed up
 * (`allowBackup="false"`, like `ThisDeviceOnly`). The ciphertext lives in private prefs as base64(iv + ciphertext).
 */
class KeystoreKeychainItem(
    private val prefs: SharedPreferences,
    private val account: String = "device-session",
    private val keyAlias: String = "shoo.token",
) : KeychainItem {
    override fun read(): String? {
        val stored = prefs.getString(account, null) ?: return null
        val key = key()
        return try {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes, 0, IV_LENGTH))
            String(cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH), Charsets.UTF_8)
        } catch (_: AEADBadTagException) {
            // Another key (reinstall, restore): this token can never be read again, like a Keychain item that
            // did not move to another iPhone.
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    override fun write(value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        // commit, not apply: the session is saved before the caller goes on (iOS writes synchronously).
        if (!prefs.edit().putString(account, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()) {
            throw IllegalStateException("Token write failed")
        }
    }

    override fun delete() {
        prefs.edit().remove(account).commit()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
    }
}

/** Tests, previews and the demo: memory only. */
class InMemoryKeychainItem(private var value: String? = null) : KeychainItem {
    /** Set to make `read()` throw, like a Keystore that can't be opened. */
    var locked = false

    @Synchronized
    override fun read(): String? {
        if (locked) throw IllegalStateException("locked")
        return value
    }

    @Synchronized
    override fun write(value: String) {
        this.value = value
    }

    @Synchronized
    override fun delete() {
        value = null
    }
}
