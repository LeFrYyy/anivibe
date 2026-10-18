package com.anivibe.app.ui.screens.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anivibe.app.core.theme.*
import com.anivibe.app.ui.components.tvFocusable

@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    onNavigateSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    val user by viewModel.currentUser.collectAsState()
    val stats by viewModel.stats.collectAsState()
    val isSyncing by viewModel.isSyncing.collectAsState()
    val syncMessage by viewModel.syncMessage.collectAsState()

    var showAuthDialog by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundDark)
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        // Top Bar
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Профиль",
                color = TextPrimaryDark,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
            IconButton(
                onClick = onNavigateSettings,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(SurfaceDark)
                    .tvFocusable(cornerRadius = 20.dp, onClick = onNavigateSettings)
            ) {
                Icon(Icons.Default.Settings, contentDescription = "Settings", tint = TextPrimaryDark)
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Profile Identity Card
        Card(
            shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceDark),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .clip(CircleShape)
                        .background(DefaultAccent),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Person,
                        contentDescription = null,
                        tint = Color.Black,
                        modifier = Modifier.size(36.dp)
                    )
                }

                Spacer(modifier = Modifier.width(16.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = user?.email ?: "Гость",
                        color = TextPrimaryDark,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = if (user != null) "Аккаунт Supabase" else "Локальный режим",
                        color = TextSecondaryDark,
                        fontSize = 13.sp
                    )
                }

                if (user == null) {
                    Button(
                        onClick = { showAuthDialog = true },
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = DefaultAccent),
                        modifier = Modifier.tvFocusable(cornerRadius = 12.dp, onClick = { showAuthDialog = true })
                    ) {
                        Text("Войти", color = Color.Black, fontWeight = FontWeight.Bold)
                    }
                } else {
                    OutlinedButton(
                        onClick = { viewModel.logout() },
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.tvFocusable(cornerRadius = 12.dp, onClick = { viewModel.logout() })
                    ) {
                        Text("Выйти", color = DangerColor)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(18.dp))

        // Supabase Sync Card
        Card(
            shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceDark),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(18.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CloudSync, contentDescription = null, tint = DefaultAccent)
                        Spacer(modifier = Modifier.width(10.dp))
                        Text(
                            text = "Синхронизация Supabase",
                            color = TextPrimaryDark,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }

                    if (user != null) {
                        Button(
                            onClick = { viewModel.syncNow() },
                            enabled = !isSyncing,
                            shape = RoundedCornerShape(10.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = DefaultAccent),
                            modifier = Modifier.tvFocusable(cornerRadius = 10.dp, onClick = { viewModel.syncNow() })
                        ) {
                            if (isSyncing) {
                                CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(16.dp))
                            } else {
                                Text("Синхронизировать", color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }

                if (syncMessage != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(text = syncMessage!!, color = SuccessColor, fontSize = 12.sp)
                }
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Stats Header
        Text(
            text = "Статистика",
            color = TextPrimaryDark,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(12.dp))

        // Stats Grid
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("Смотрю", stats.watching.toString(), Modifier.weight(1f))
            StatCard("Просмотрено", stats.completed.toString(), Modifier.weight(1f))
            StatCard("Запланировано", stats.planned.toString(), Modifier.weight(1f))
        }
        Spacer(modifier = Modifier.height(10.dp))
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("Отложено", stats.onHold.toString(), Modifier.weight(1f))
            StatCard("Брошено", stats.dropped.toString(), Modifier.weight(1f))
            StatCard("Избранное", stats.favorites.toString(), Modifier.weight(1f))
        }
    }

    if (showAuthDialog) {
        AuthDialog(
            onDismiss = { showAuthDialog = false },
            onLogin = { email, pass, cb -> viewModel.login(email, pass, cb) },
            onSignup = { email, pass, cb -> viewModel.signup(email, pass, cb) }
        )
    }
}

@Composable
fun StatCard(label: String, value: String, modifier: Modifier = Modifier) {
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = SurfaceDark),
        modifier = modifier
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(text = value, color = DefaultAccent, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(2.dp))
            Text(text = label, color = TextSecondaryDark, fontSize = 11.sp)
        }
    }
}

@Composable
fun AuthDialog(
    onDismiss: () -> Unit,
    onLogin: (String, String, (Boolean, String?) -> Unit) -> Unit,
    onSignup: (String, String, (Boolean, String?) -> Unit) -> Unit
) {
    var isRegisterMode by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isLoading by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isRegisterMode) "Регистрация" else "Вход в Supabase", color = TextPrimaryDark) },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("Email") },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = TextPrimaryDark,
                        unfocusedTextColor = TextPrimaryDark,
                        focusedBorderColor = DefaultAccent
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Пароль") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = TextPrimaryDark,
                        unfocusedTextColor = TextPrimaryDark,
                        focusedBorderColor = DefaultAccent
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
                if (errorMessage != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(errorMessage!!, color = DangerColor, fontSize = 12.sp)
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    isLoading = true
                    errorMessage = null
                    val callback: (Boolean, String?) -> Unit = { success, error ->
                        isLoading = false
                        if (success) {
                            onDismiss()
                        } else {
                            errorMessage = error
                        }
                    }
                    if (isRegisterMode) {
                        onSignup(email, password, callback)
                    } else {
                        onLogin(email, password, callback)
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = DefaultAccent)
            ) {
                Text(if (isRegisterMode) "Создать аккаунт" else "Войти", color = Color.Black)
            }
        },
        dismissButton = {
            TextButton(onClick = { isRegisterMode = !isRegisterMode }) {
                Text(if (isRegisterMode) "Уже есть аккаунт? Войти" else "Регистрация", color = TextSecondaryDark)
            }
        },
        containerColor = SurfaceDark
    )
}
