package com.anivibe.app.ui.screens.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anivibe.app.core.theme.*
import com.anivibe.app.data.model.Anime
import com.anivibe.app.data.model.ContinueWatchingItem
import com.anivibe.app.ui.components.ErrorView
import com.anivibe.app.ui.components.LoadingView
import com.anivibe.app.ui.components.PosterCard
import com.anivibe.app.ui.components.tvFocusable

@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onAnimeClick: (Int) -> Unit,
    onContinueClick: (animeId: Int, episode: Int, sourceKey: String?) -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val continueWatching by viewModel.continueWatching.collectAsState()
    val collections by viewModel.collections.collectAsState()

    when (val state = uiState) {
        is HomeUiState.Loading -> LoadingView(modifier = modifier)
        is HomeUiState.Error -> ErrorView(
            message = state.message,
            onRetry = { viewModel.loadFeed() },
            modifier = modifier
        )
        is HomeUiState.Success -> {
            LazyColumn(
                modifier = modifier
                    .fillMaxSize()
                    .background(BackgroundDark),
                contentPadding = PaddingValues(vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                // Continue Watching Row
                if (continueWatching.isNotEmpty()) {
                    item {
                        Column {
                            SectionHeader(title = "Продолжить просмотр")
                            LazyRow(
                                contentPadding = PaddingValues(horizontal = 16.dp),
                                horizontalArrangement = Arrangement.spacedBy(14.dp)
                            ) {
                                items(continueWatching, key = { it.animeId }) { item ->
                                    ContinueWatchingCard(
                                        item = item,
                                        onClick = { onContinueClick(item.animeId, item.episode, item.sourceKey) }
                                    )
                                }
                            }
                        }
                    }
                }

                // Collections row if any exist
                if (collections.isNotEmpty()) {
                    item {
                        Column {
                            SectionHeader(title = "Мои папки")
                            LazyRow(
                                contentPadding = PaddingValues(horizontal = 16.dp),
                                horizontalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                items(collections, key = { it.id }) { col ->
                                    Row(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(SurfaceDark)
                                            .padding(horizontal = 16.dp, vertical = 10.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Text(text = col.emoji, fontSize = 18.sp)
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text(
                                            text = "${col.name} (${col.animeIds.size})",
                                            color = TextPrimaryDark,
                                            fontWeight = FontWeight.SemiBold,
                                            fontSize = 13.sp
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                // Recommendations
                if (state.recommendations.isNotEmpty()) {
                    item {
                        AnimeSection(
                            title = "Рекомендуем вам",
                            items = state.recommendations,
                            onAnimeClick = onAnimeClick
                        )
                    }
                }

                // Trending
                item {
                    AnimeSection(
                        title = "В тренде",
                        items = state.trending,
                        onAnimeClick = onAnimeClick
                    )
                }

                // Seasonal
                item {
                    AnimeSection(
                        title = "Сейчас в эфире",
                        items = state.seasonal,
                        onAnimeClick = onAnimeClick
                    )
                }

                // Popular
                item {
                    AnimeSection(
                        title = "Популярное за всё время",
                        items = state.popular,
                        onAnimeClick = onAnimeClick
                    )
                }

                // Recent
                item {
                    AnimeSection(
                        title = "Недавние релизы",
                        items = state.recent,
                        onAnimeClick = onAnimeClick
                    )
                }
            }
        }
    }
}

@Composable
fun SectionHeader(title: String) {
    Text(
        text = title,
        color = TextPrimaryDark,
        fontSize = 19.sp,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
    )
}

@Composable
fun AnimeSection(
    title: String,
    items: List<Anime>,
    onAnimeClick: (Int) -> Unit
) {
    Column {
        SectionHeader(title = title)
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(items, key = { it.id }) { anime ->
                PosterCard(anime = anime, onClick = { onAnimeClick(anime.id) })
            }
        }
    }
}

@Composable
fun ContinueWatchingCard(
    item: ContinueWatchingItem,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .width(260.dp)
            .height(90.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(SurfaceDark)
            .clickable { onClick() }
            .tvFocusable(cornerRadius = 16.dp, onClick = onClick)
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .width(55.dp)
                .fillMaxHeight()
                .clip(RoundedCornerShape(10.dp))
                .background(SurfaceElevatedDark)
        ) {
            AsyncImage(
                model = item.coverUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0x44000000)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.PlayArrow,
                    contentDescription = "Play",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = item.title,
                color = TextPrimaryDark,
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = "Серия ${item.episode}",
                color = TextSecondaryDark,
                fontSize = 11.sp
            )
            Spacer(modifier = Modifier.height(6.dp))
            LinearProgressIndicator(
                progress = { (item.percent / 100f).coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = DefaultAccent,
                trackColor = SeparatorDark
            )
        }
    }
}
