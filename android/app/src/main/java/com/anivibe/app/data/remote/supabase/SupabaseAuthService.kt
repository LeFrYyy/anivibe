package com.anivibe.app.data.remote.supabase

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AuthSessionResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("token_type") val tokenType: String = "bearer",
    @SerialName("expires_in") val expiresIn: Long = 3600,
    @SerialName("refresh_token") val refreshToken: String,
    val user: SupabaseUserDto
)

@Serializable
data class SupabaseUserDto(
    val id: String,
    val email: String? = null
)

@Serializable
data class AuthEmailPasswordRequest(
    val email: String,
    val password: String
)

@Serializable
data class AuthRefreshTokenRequest(
    @SerialName("refresh_token") val refreshToken: String
)

class SupabaseAuthService(
    private val client: HttpClient,
    private val supabaseUrl: String,
    private val anonKey: String,
    context: Context
) {
    private val prefs: SharedPreferences = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "anivibe_secure_auth",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (e: Exception) {
        context.getSharedPreferences("anivibe_auth_prefs", Context.MODE_PRIVATE)
    }

    private val _currentUser = MutableStateFlow(loadStoredUser())
    val currentUser: StateFlow<SupabaseUserDto?> = _currentUser.asStateFlow()

    private fun loadStoredUser(): SupabaseUserDto? {
        val id = prefs.getString("user_id", null) ?: return null
        val email = prefs.getString("user_email", null)
        return SupabaseUserDto(id, email)
    }

    fun getAccessToken(): String? = prefs.getString("access_token", null)
    private fun getRefreshToken(): String? = prefs.getString("refresh_token", null)

    suspend fun signup(email: String, password: String): SupabaseUserDto {
        val url = "$supabaseUrl/auth/v1/signup"
        val response: AuthSessionResponse = client.post(url) {
            contentType(ContentType.Application.Json)
            header("apikey", anonKey)
            setBody(AuthEmailPasswordRequest(email, password))
        }.body()

        saveSession(response)
        return response.user
    }

    suspend fun login(email: String, password: String): SupabaseUserDto {
        val url = "$supabaseUrl/auth/v1/token?grant_type=password"
        val response: AuthSessionResponse = client.post(url) {
            contentType(ContentType.Application.Json)
            header("apikey", anonKey)
            setBody(AuthEmailPasswordRequest(email, password))
        }.body()

        saveSession(response)
        return response.user
    }

    suspend fun refreshSession(): String? {
        val token = getRefreshToken() ?: return null
        val url = "$supabaseUrl/auth/v1/token?grant_type=refresh_token"
        return try {
            val response: AuthSessionResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header("apikey", anonKey)
                setBody(AuthRefreshTokenRequest(token))
            }.body()
            saveSession(response)
            response.accessToken
        } catch (e: Exception) {
            logout()
            null
        }
    }

    fun logout() {
        prefs.edit().clear().apply()
        _currentUser.value = null
    }

    private fun saveSession(session: AuthSessionResponse) {
        prefs.edit()
            .putString("access_token", session.accessToken)
            .putString("refresh_token", session.refreshToken)
            .putString("user_id", session.user.id)
            .putString("user_email", session.user.email)
            .apply()
        _currentUser.value = session.user
    }
}
