package com.anivibe.app

import android.app.PictureInPictureParams
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import com.anivibe.app.core.theme.AnivibeTheme
import com.anivibe.app.core.theme.DefaultAccent
import com.anivibe.app.ui.navigation.AnivibeNavGraph
import com.anivibe.app.ui.screens.settings.availableAccents

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val app = application as AnivibeApplication

        setContent {
            val settingsPrefs = remember { getSharedPreferences("anivibe_settings", Context.MODE_PRIVATE) }
            val accentIndex = remember { mutableStateOf(settingsPrefs.getInt("accent_index", 0)) }
            val currentAccent = availableAccents.getOrNull(accentIndex.value)?.first ?: DefaultAccent

            AnivibeTheme(accentColor = currentAccent) {
                AnivibeNavGraph(app = app)
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Enter Picture-in-Picture automatically when minimizing during video playback
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                enterPictureInPictureMode(params)
            } catch (e: Exception) {
                // Ignore if PiP not supported on specific vendor device
            }
        }
    }
}
