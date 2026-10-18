package com.anivibe.app.ui.screens.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.anivibe.app.data.model.UserStats
import com.anivibe.app.data.remote.supabase.SupabaseUserDto
import com.anivibe.app.data.repository.LibraryRepository
import com.anivibe.app.data.repository.SessionRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ProfileViewModel(
    private val sessionRepository: SessionRepository,
    private val libraryRepository: LibraryRepository
) : ViewModel() {

    val currentUser: StateFlow<SupabaseUserDto?> = sessionRepository.currentUser

    private val _stats = MutableStateFlow(UserStats())
    val stats: StateFlow<UserStats> = _stats.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _syncMessage = MutableStateFlow<String?>(null)
    val syncMessage: StateFlow<String?> = _syncMessage.asStateFlow()

    init {
        loadStats()
    }

    fun loadStats() {
        viewModelScope.launch {
            _stats.value = libraryRepository.getStats()
        }
    }

    fun syncNow() {
        viewModelScope.launch {
            _isSyncing.value = true
            _syncMessage.value = null
            val success = sessionRepository.syncNow()
            _isSyncing.value = false
            _syncMessage.value = if (success) "Синхронизация успешна" else "Ошибка синхронизации"
            loadStats()
        }
    }

    fun login(email: String, pass: String, onResult: (Boolean, String?) -> Unit) {
        viewModelScope.launch {
            val result = sessionRepository.login(email, pass)
            result.onSuccess {
                loadStats()
                onResult(true, null)
            }.onFailure {
                onResult(false, it.message ?: "Ошибка входа")
            }
        }
    }

    fun signup(email: String, pass: String, onResult: (Boolean, String?) -> Unit) {
        viewModelScope.launch {
            val result = sessionRepository.signup(email, pass)
            result.onSuccess {
                loadStats()
                onResult(true, null)
            }.onFailure {
                onResult(false, it.message ?: "Ошибка регистрации")
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            sessionRepository.logout()
            loadStats()
        }
    }
}
