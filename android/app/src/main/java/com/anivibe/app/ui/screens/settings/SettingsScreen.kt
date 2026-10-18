package com.anivibe.app.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anivibe.app.core.theme.*
import com.anivibe.app.ui.components.tvFocusable

val availableAccents = listOf(
    DefaultAccent to "Фиолетовый",
    SecondaryAccent to "Голубой",
    Color(0xFFFF7043) to "Оранжевый",
    Color(0xFFEC407A) to "Розовый",
    SuccessColor to "Изумрудный"
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val kodikToken by viewModel.kodikToken.collectAsState()
    val accentIndex by viewModel.accentIndex.collectAsState()
    val anilibriaEnabled by viewModel.anilibriaEnabled.collectAsState()

    var tempToken by remember(kodikToken) { mutableStateOf(kodikToken) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundDark)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(SurfaceDark)
                    .tvFocusable(cornerRadius = 20.dp, onClick = onBack)
            ) {
                Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = TextPrimaryDark)
            }
            Spacer(modifier = Modifier.width(14.dp))
            Text(
                text = "Настройки",
                color = TextPrimaryDark,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Kodik API Token Setting
        Text("Источники видео", color = DefaultAccent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))

        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceDark),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "Партнёрский токен Kodik API",
                    color = TextPrimaryDark,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Используется для поиска и воспроизведения десятков озвучек с kodik.biz",
                    color = TextSecondaryDark,
                    fontSize = 12.sp
                )
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = tempToken,
                    onValueChange = {
                        tempToken = it
                        viewModel.updateKodikToken(it)
                    },
                    placeholder = { Text("Вставьте токен kodik...", color = TextSecondaryDark) },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = TextPrimaryDark,
                        unfocusedTextColor = TextPrimaryDark,
                        focusedBorderColor = DefaultAccent
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Anilibria Toggle
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceDark),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Включить Anilibria",
                        color = TextPrimaryDark,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Официальные HLS-потоки релизов Анилибрии",
                        color = TextSecondaryDark,
                        fontSize = 12.sp
                    )
                }
                Switch(
                    checked = anilibriaEnabled,
                    onCheckedChange = { viewModel.toggleAnilibria(it) },
                    colors = SwitchDefaults.colors(checkedThumbColor = DefaultAccent)
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Accent Theme Setting
        Text("Оформление", color = DefaultAccent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))

        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceDark),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "Цветовой акцент",
                    color = TextPrimaryDark,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    availableAccents.forEachIndexed { index, (color, _) ->
                        Box(
                            modifier = Modifier
                                .size(42.dp)
                                .clip(CircleShape)
                                .background(color)
                                .clickable { viewModel.selectAccent(index) }
                                .tvFocusable(cornerRadius = 21.dp, onClick = { viewModel.selectAccent(index) }),
                            contentAlignment = Alignment.Center
                        ) {
                            if (accentIndex == index) {
                                Box(
                                    modifier = Modifier
                                        .size(16.dp)
                                        .clip(CircleShape)
                                        .background(Color.White)
                                )
                            }
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // About
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceDark),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Anivibe Android", color = TextPrimaryDark, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(4.dp))
                Text("Версия: 1.0.0 (Native Kotlin + Jetpack Compose)", color = TextSecondaryDark, fontSize = 12.sp)
                Text("Плеер: Media3 ExoPlayer (HLS, MP4, PiP)", color = TextSecondaryDark, fontSize = 12.sp)
                Text("Синхронизация: Supabase PostgREST + Room", color = TextSecondaryDark, fontSize = 12.sp)
            }
        }
    }
}
