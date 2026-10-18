package com.anivibe.app.ui.screens.player

import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import com.anivibe.app.core.theme.DefaultAccent
import com.anivibe.app.core.theme.SurfaceDark
import com.anivibe.app.core.theme.TextPrimaryDark
import com.anivibe.app.core.theme.TextSecondaryDark
import com.anivibe.app.ui.components.tvFocusable
import kotlinx.coroutines.delay

@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    viewModel: PlayerViewModel,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val state by viewModel.state.collectAsState()
    var areControlsVisible by remember { mutableStateOf(true) }
    var showQualityMenu by remember { mutableStateOf(false) }

    // Auto-hide controls after 3 seconds when playing
    LaunchedEffect(areControlsVisible, state.isPlaying) {
        if (areControlsVisible && state.isPlaying) {
            delay(3500)
            areControlsVisible = false
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusable()
            .onKeyEvent { event ->
                if (event.type == KeyEventType.KeyDown) {
                    when (event.key) {
                        Key.DirectionCenter, Key.Enter, Key.NumPadEnter -> {
                            viewModel.togglePlayPause()
                            areControlsVisible = true
                            true
                        }
                        Key.DirectionLeft -> {
                            viewModel.seekRelative(-10)
                            areControlsVisible = true
                            true
                        }
                        Key.DirectionRight -> {
                            viewModel.seekRelative(10)
                            areControlsVisible = true
                            true
                        }
                        Key.DirectionUp, Key.DirectionDown -> {
                            areControlsVisible = !areControlsVisible
                            true
                        }
                        Key.Back -> {
                            onClose()
                            true
                        }
                        else -> false
                    }
                } else false
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                areControlsVisible = !areControlsVisible
            }
    ) {
        if (state.useWebPlayerFallback && !state.currentEpisode?.webPlayerUrl.isNullOrEmpty()) {
            KodikWebViewPlayer(playerUrl = state.currentEpisode!!.webPlayerUrl!!)
        } else {
            // Media3 ExoPlayer Native View
            AndroidView(
                factory = { context ->
                    PlayerView(context).apply {
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                        useController = false
                        player = viewModel.exoPlayer
                    }
                },
                update = { view ->
                    view.player = viewModel.exoPlayer
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        // Buffering Indicator
        if (state.isBuffering) {
            CircularProgressIndicator(
                color = DefaultAccent,
                modifier = Modifier
                    .size(54.dp)
                    .align(Alignment.Center)
            )
        }

        // HUD Overlay Controls
        AnimatedVisibility(
            visible = areControlsVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize()
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0x77000000))
                    .padding(20.dp)
            ) {
                // Top Bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .align(Alignment.TopCenter),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = onClose,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color(0x66000000))
                            .tvFocusable(cornerRadius = 24.dp, onClick = onClose)
                    ) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Close", tint = Color.White)
                    }

                    Spacer(modifier = Modifier.width(12.dp))

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = state.anime?.displayTitle ?: "Воспроизведение",
                            color = Color.White,
                            fontSize = 16.sp,
                            maxLines = 1
                        )
                        Text(
                            text = state.currentEpisode?.title ?: "Серия ${state.currentEpisodeNumber}",
                            color = TextSecondaryDark,
                            fontSize = 12.sp
                        )
                    }

                    // Quality Selector Button
                    if (state.availableQualities.isNotEmpty()) {
                        Box {
                            TextButton(
                                onClick = { showQualityMenu = true },
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(Color(0x66000000))
                                    .tvFocusable(cornerRadius = 8.dp, onClick = { showQualityMenu = true })
                            ) {
                                Text(
                                    text = state.selectedQuality?.let { "${it}p" } ?: "Качество",
                                    color = Color.White,
                                    fontSize = 12.sp
                                )
                            }

                            DropdownMenu(
                                expanded = showQualityMenu,
                                onDismissRequest = { showQualityMenu = false },
                                modifier = Modifier.background(SurfaceDark)
                            ) {
                                state.availableQualities.forEach { stream ->
                                    DropdownMenuItem(
                                        text = { Text(stream.label, color = TextPrimaryDark) },
                                        onClick = {
                                            viewModel.selectQuality(stream.quality)
                                            showQualityMenu = false
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                // Center Controls (Rewind, Play/Pause, Fast Forward)
                Row(
                    modifier = Modifier.align(Alignment.Center),
                    horizontalArrangement = Arrangement.spacedBy(28.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = { viewModel.seekRelative(-10) },
                        modifier = Modifier
                            .size(54.dp)
                            .clip(CircleShape)
                            .background(Color(0x55000000))
                            .tvFocusable(cornerRadius = 27.dp, onClick = { viewModel.seekRelative(-10) })
                    ) {
                        Icon(Icons.Default.Replay10, contentDescription = "Rewind", tint = Color.White, modifier = Modifier.size(32.dp))
                    }

                    IconButton(
                        onClick = { viewModel.togglePlayPause() },
                        modifier = Modifier
                            .size(72.dp)
                            .clip(CircleShape)
                            .background(DefaultAccent)
                            .tvFocusable(cornerRadius = 36.dp, onClick = { viewModel.togglePlayPause() })
                    ) {
                        Icon(
                            imageVector = if (state.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = "Play/Pause",
                            tint = Color.Black,
                            modifier = Modifier.size(42.dp)
                        )
                    }

                    IconButton(
                        onClick = { viewModel.seekRelative(10) },
                        modifier = Modifier
                            .size(54.dp)
                            .clip(CircleShape)
                            .background(Color(0x55000000))
                            .tvFocusable(cornerRadius = 27.dp, onClick = { viewModel.seekRelative(10) })
                    ) {
                        Icon(Icons.Default.Forward10, contentDescription = "Forward", tint = Color.White, modifier = Modifier.size(32.dp))
                    }
                }

                // Bottom Timeline Controls
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                ) {
                    Slider(
                        value = if (state.duration > 0) state.currentPosition.toFloat() / state.duration.toFloat() else 0f,
                        onValueChange = { fraction ->
                            viewModel.seekToPosition((fraction * state.duration).toLong())
                        },
                        colors = SliderDefaults.colors(
                            thumbColor = DefaultAccent,
                            activeTrackColor = DefaultAccent,
                            inactiveTrackColor = Color(0x66FFFFFF)
                        ),
                        modifier = Modifier.fillMaxWidth()
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = formatTime(state.currentPosition),
                            color = Color.White,
                            fontSize = 12.sp
                        )

                        // Next Episode Button
                        val hasNext = state.episodes.any { it.episodeNumber == state.currentEpisodeNumber + 1 }
                        if (hasNext) {
                            TextButton(
                                onClick = { viewModel.playNextEpisode() },
                                modifier = Modifier.tvFocusable(cornerRadius = 8.dp, onClick = { viewModel.playNextEpisode() })
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text("След. серия", color = Color.White, fontSize = 12.sp)
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Icon(Icons.Default.SkipNext, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                                }
                            }
                        }

                        Text(
                            text = formatTime(state.duration),
                            color = Color.White,
                            fontSize = 12.sp
                        )
                    }
                }
            }
        }
    }
}

fun formatTime(millis: Long): String {
    val totalSeconds = (millis / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    val hours = minutes / 60
    return if (hours > 0) {
        String.format("%d:%02d:%02d", hours, minutes % 60, seconds)
    } else {
        String.format("%02d:%02d", minutes, seconds)
    }
}
