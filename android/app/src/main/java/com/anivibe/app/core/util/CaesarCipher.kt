package com.anivibe.app.core.util

import android.util.Base64

object CaesarCipher {

    fun decodeKodikSource(src: String): String? {
        if (src.contains("//")) return src

        val shifts = listOf(18) + (0 until 26).filter { it != 18 }
        for (shift in shifts) {
            val shifted = caesar(src, shift)
            val decoded = base64Decode(shifted)
            if (decoded != null && decoded.contains("//") && (decoded.contains("m3u8") || decoded.contains(".mp4"))) {
                return decoded
            }
        }
        return null
    }

    fun caesar(text: String, shift: Int): String {
        val result = StringBuilder(text.length)
        for (ch in text) {
            when (ch) {
                in 'A'..'Z' -> {
                    val base = 'A'.code
                    val newChar = ((ch.code - base + shift) % 26 + base).toChar()
                    result.append(newChar)
                }
                in 'a'..'z' -> {
                    val base = 'a'.code
                    val newChar = ((ch.code - base + shift) % 26 + base).toChar()
                    result.append(newChar)
                }
                else -> result.append(ch)
            }
        }
        return result.toString()
    }

    fun base64Decode(text: String): String? {
        return try {
            var s = text.replace("-", "+").replace("_", "/")
            while (s.length % 4 != 0) {
                s += "="
            }
            val bytes = Base64.decode(s, Base64.DEFAULT)
            String(bytes, Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }
}
