package com.anivibe.app.data.repository

import com.anivibe.app.data.remote.supabase.SupabaseAuthService
import com.anivibe.app.data.remote.supabase.SupabaseSyncManager
import com.anivibe.app.data.remote.supabase.SupabaseUserDto
import kotlinx.coroutines.flow.StateFlow

class SessionRepository(
    private val authService: SupabaseAuthService,
    private val syncManager: SupabaseSyncManager
) {
    val currentUser: StateFlow<SupabaseUserDto?> = authService.currentUser

    suspend fun login(email: String, pass: String): Result<SupabaseUserDto> {
        return try {
            val user = authService.login(email, pass)
            syncManager.sync()
            Result.success(user)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun signup(email: String, pass: String): Result<SupabaseUserDto> {
        return try {
            val user = authService.signup(email, pass)
            syncManager.sync()
            Result.success(user)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun logout() {
        authService.logout()
    }

    suspend fun syncNow(): Boolean {
        return syncManager.sync()
    }
}
