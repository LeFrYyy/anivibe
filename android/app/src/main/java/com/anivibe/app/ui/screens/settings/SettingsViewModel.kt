package com.anivibe.app.ui.screens.settings

import android.content.Context
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class SettingsViewModel(
    context: Context
) : ViewModel() {

    private val prefs = context.getSharedPreferences("anivibe_settings", Context.MODE_PRIVATE)

    private val _kodikToken = MutableStateFlow(prefs.getString("kodik_token", "") ?: "")
    val kodikToken: StateFlow<String> = _kodikToken.asStateFlow()

    private val _accentIndex = MutableStateFlow(prefs.getInt("accent_index", 0))
    val accentIndex: StateFlow<Int> = _accentIndex.asStateFlow()

    private val _anilibriaEnabled = MutableStateFlow(prefs.getBoolean("anilibria_enabled", true))
    val anilibriaEnabled: StateFlow<Boolean> = _anilibriaEnabled.asStateFlow()

    fun updateKodikToken(token: String) {
        _kodikToken.value = token
        prefs.edit().putString("kodik_token", token.trim()).apply()
    }

    fun selectAccent(index: Int) {
        _accentIndex.value = index
        prefs.edit().putInt("accent_index", index).apply()
    }

    fun toggleAnilibria(enabled: Boolean) {
        _anilibriaEnabled.value = enabled
        prefs.edit().putBoolean("anilibria_enabled", enabled).apply()
    }
}
