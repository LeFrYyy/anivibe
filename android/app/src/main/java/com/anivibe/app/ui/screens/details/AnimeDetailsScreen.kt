package com.anivibe.app.ui.screens.details

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anivibe.app.core.theme.*
import com.anivibe.app.data.model.LibraryStatus
import com.anivibe.app.data.model.ProviderEpisode
import com.anivibe.app.ui.components.*
import com.anivibe.app.ui.screens.home.SectionHeader

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AnimeDetailsScreen(
    viewModel: AnimeDetailsViewModel,
    onBack: () -> Unit,
    onPlayEpisode: (animeId: Int, episode: Int, sourceKey: String?) -> Unit,
    onAnimeClick: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val entry by viewModel.libraryEntry.collectAsState()
    val progressList by viewModel.watchProgress.collectAsState()

    var showStatusMenu by remember { mutableStateOf(false) }

    when (val state = uiState) {
        is DetailsUiState.Loading -> LoadingView()
        is DetailsUiState.Error -> ErrorView(
            message = state.message,
            onRetry = { viewModel.loadDetails() }
        )
        is DetailsUiState.Success -> {
            val anime = state.anime
            val progressMap = remember(progressList) { progressList.associateBy { it.episode } }

            LazyColumn(
                modifier = modifier
                    .fillMaxSize()
                    .background(BackgroundDark),
                contentPadding = PaddingValues(bottom = 32.dp)
            ) {
                // Banner & Header
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(280.dp)
                    ) {
                        AsyncImage(
                            model = anime.bannerImage ?: anime.coverImage?.bestUrl,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(
                                    Brush.verticalGradient(
                                        colors = listOf(
                                            Color(0x88000000),
                                            BackgroundDark
                                        )
                                    )
                                )
                        )

                        // Back Button
                        IconButton(
                            onClick = onBack,
                            modifier = Modifier
                                .statusBarsPadding()
                                .padding(12.dp)
                                .clip(CircleShape)
                                .background(Color(0x88000000))
                                .tvFocusable(cornerRadius = 24.dp, onClick = onBack)
                        ) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = Color.White)
                        }
                    }
                }

                // Info Section
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .offset(y = (-60).dp)
                            .padding(horizontal = 16.dp)
                    ) {
                        // Poster
                        Box(
                            modifier = Modifier
                                .width(120.dp)
                                .aspectRatio(2.0f / 3.0f)
                                .clip(RoundedCornerShape(16.dp))
                                .background(SurfaceElevatedDark)
                        ) {
                            AsyncImage(
                                model = anime.coverImage?.bestUrl,
                                contentDescription = anime.displayTitle,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        Spacer(modifier = Modifier.width(16.dp))

                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = anime.displayTitle,
                                color = TextPrimaryDark,
                                fontSize = 20.sp,
                                fontWeight = FontWeight.Bold,
                                lineHeight = 24.sp
                            )

                            if (anime.title.romaji != null && anime.title.romaji != anime.displayTitle) {
                                Text(
                                    text = anime.title.romaji,
                                    color = TextSecondaryDark,
                                    fontSize = 12.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            Spacer(modifier = Modifier.height(8.dp))

                            // Badges (Score, Year, Format)
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                if (anime.averageScore != null && anime.averageScore > 0) {
                                    BadgeItem(icon = Icons.Default.Star, text = anime.scoreText, iconColor = StarGold)
                                }
                                if (anime.seasonYear != null) {
                                    BadgeItem(text = anime.seasonYear.toString())
                                }
                                if (anime.format != null) {
                                    BadgeItem(text = anime.format.displayName)
                                }
                                if (anime.status != null) {
                                    BadgeItem(text = anime.status.displayName)
                                }
                            }
                        }
                    }
                }

                // Action Buttons (Play & Status)
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .offset(y = (-40).dp)
                            .padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        // Watch Button
                        Button(
                            onClick = {
                                val targetEp = entry?.lastEpisode ?: 1
                                val epItem = state.episodes.firstOrNull { it.episodeNumber == targetEp } ?: state.episodes.firstOrNull()
                                onPlayEpisode(anime.id, targetEp, epItem?.sourceKey)
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = DefaultAccent),
                            shape = RoundedCornerShape(14.dp),
                            modifier = Modifier
                                .weight(1f)
                                .height(48.dp)
                                .tvFocusable(cornerRadius = 14.dp)
                        ) {
                            Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Color.Black)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = if (entry?.lastEpisode != null) "Продолжить (${entry?.lastEpisode} эп.)" else "Смотреть",
                                color = Color.Black,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp
                            )
                        }

                        // Add to Library Status Button
                        Box {
                            FilledTonalButton(
                                onClick = { showStatusMenu = true },
                                shape = RoundedCornerShape(14.dp),
                                colors = ButtonDefaults.filledTonalButtonColors(
                                    containerColor = if (entry?.status != null) SurfaceElevatedDark else SurfaceDark
                                ),
                                modifier = Modifier
                                    .height(48.dp)
                                    .tvFocusable(cornerRadius = 14.dp, onClick = { showStatusMenu = true })
                            ) {
                                Icon(Icons.Default.Bookmark, contentDescription = null, tint = TextPrimaryDark)
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    text = entry?.status?.title ?: "В список",
                                    color = TextPrimaryDark,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }

                            DropdownMenu(
                                expanded = showStatusMenu,
                                onDismissRequest = { showStatusMenu = false },
                                modifier = Modifier.background(SurfaceElevatedDark)
                            ) {
                                LibraryStatus.entries.forEach { status ->
                                    DropdownMenuItem(
                                        text = { Text(status.title, color = TextPrimaryDark) },
                                        onClick = {
                                            viewModel.setStatus(if (entry?.status == status) null else status)
                                            showStatusMenu = false
                                        }
                                    )
                                }
                            }
                        }

                        // Favorite Button
                        IconButton(
                            onClick = { viewModel.toggleFavorite() },
                            modifier = Modifier
                                .size(48.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(SurfaceDark)
                                .tvFocusable(cornerRadius = 14.dp, onClick = { viewModel.toggleFavorite() })
                        ) {
                            Icon(
                                imageVector = if (entry?.isFavorite == true) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                                contentDescription = "Favorite",
                                tint = if (entry?.isFavorite == true) DangerColor else TextSecondaryDark
                            )
                        }
                    }
                }

                // Synopsis
                if (!anime.synopsis.isNullOrBlank()) {
                    item {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .offset(y = (-20).dp)
                                .padding(horizontal = 16.dp)
                        ) {
                            Text("Описание", color = TextPrimaryDark, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                            Spacer(modifier = Modifier.height(6.dp))
                            Text(
                                text = anime.synopsis,
                                color = TextSecondaryDark,
                                fontSize = 14.sp,
                                lineHeight = 20.sp
                            )
                        }
                    }
                }

                // Voice Acting / Translations (Kodik & Anilibria)
                if (state.kodikMaterials.isNotEmpty()) {
                    item {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp)
                        ) {
                            Text("Озвучки онлайн (Kodik)", color = TextPrimaryDark, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                            Spacer(modifier = Modifier.height(10.dp))
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                items(state.kodikMaterials, key = { it.id }) { mat ->
                                    val isSelected = state.selectedMaterial?.id == mat.id
                                    FilterChip(
                                        selected = isSelected,
                                        onClick = { viewModel.selectTranslation(mat) },
                                        label = {
                                            Text(
                                                text = mat.translation?.title ?: "Оригинал",
                                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                // Episodes list
                if (state.episodes.isNotEmpty()) {
                    item {
                        Text(
                            text = "Серии (${state.episodes.size})",
                            color = TextPrimaryDark,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }

                    items(state.episodes, key = { it.sourceKey }) { ep ->
                        val prog = progressMap[ep.episodeNumber]
                        EpisodeRowItem(
                            episode = ep,
                            progress = prog,
                            onClick = { onPlayEpisode(anime.id, ep.episodeNumber, ep.sourceKey) }
                        )
                    }
                }

                // Recommendations
                if (anime.recommendations.isNotEmpty()) {
                    item {
                        Spacer(modifier = Modifier.height(16.dp))
                        SectionHeader(title = "Похожие аниме")
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            items(anime.recommendations, key = { it.id }) { rec ->
                                PosterCard(anime = rec, onClick = { onAnimeClick(rec.id) })
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun BadgeItem(icon: androidx.compose.ui.graphics.vector.ImageVector? = null, text: String, iconColor: Color = Color.White) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(SurfaceDark)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = iconColor, modifier = Modifier.size(12.dp))
            Spacer(modifier = Modifier.width(4.dp))
        }
        Text(text = text, color = TextPrimaryDark, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun EpisodeRowItem(
    episode: ProviderEpisode,
    progress: com.anivibe.app.data.model.WatchProgress?,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(SurfaceDark)
            .clickable { onClick() }
            .tvFocusable(cornerRadius = 12.dp, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.PlayCircleOutline, contentDescription = null, tint = DefaultAccent)
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(text = episode.title ?: "Серия ${episode.episodeNumber}", color = TextPrimaryDark, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            if (progress != null && progress.positionSeconds > 0) {
                Text(text = "${progress.percent}% просмотрено", color = TextSecondaryDark, fontSize = 11.sp)
            }
        }
        if (progress?.isFinished == true) {
            Icon(Icons.Default.CheckCircle, contentDescription = "Finished", tint = SuccessColor, modifier = Modifier.size(18.dp))
        }
    }
}
