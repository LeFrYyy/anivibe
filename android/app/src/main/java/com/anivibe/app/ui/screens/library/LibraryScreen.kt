package com.anivibe.app.ui.screens.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anivibe.app.core.theme.*
import com.anivibe.app.data.model.Anime
import com.anivibe.app.data.model.AnimeCoverImage
import com.anivibe.app.data.model.AnimeTitle
import com.anivibe.app.data.model.LibraryEntry
import com.anivibe.app.data.model.WatchHistoryItem
import com.anivibe.app.ui.components.EmptyStateView
import com.anivibe.app.ui.components.PosterCard
import com.anivibe.app.ui.components.tvFocusable
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun LibraryScreen(
    viewModel: LibraryViewModel,
    onAnimeClick: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val selectedTab by viewModel.selectedTab.collectAsState()

    val watchingList by viewModel.watchingList.collectAsState()
    val completedList by viewModel.completedList.collectAsState()
    val plannedList by viewModel.plannedList.collectAsState()
    val onHoldList by viewModel.onHoldList.collectAsState()
    val droppedList by viewModel.droppedList.collectAsState()
    val favoritesList by viewModel.favoritesList.collectAsState()
    val historyList by viewModel.historyList.collectAsState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundDark)
    ) {
        Text(
            text = "Моя библиотека",
            color = TextPrimaryDark,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp)
        )

        ScrollableTabRow(
            selectedTabIndex = selectedTab.ordinal,
            containerColor = BackgroundDark,
            contentColor = DefaultAccent,
            edgePadding = 16.dp,
            divider = { HorizontalDivider(color = SeparatorDark) }
        ) {
            LibraryTab.entries.forEach { tab ->
                val count = when (tab) {
                    LibraryTab.WATCHING -> watchingList.size
                    LibraryTab.COMPLETED -> completedList.size
                    LibraryTab.PLANNED -> plannedList.size
                    LibraryTab.ON_HOLD -> onHoldList.size
                    LibraryTab.DROPPED -> droppedList.size
                    LibraryTab.FAVORITES -> favoritesList.size
                    LibraryTab.HISTORY -> historyList.size
                }
                Tab(
                    selected = selectedTab == tab,
                    onClick = { viewModel.selectTab(tab) },
                    text = {
                        Text(
                            text = "${tab.title} ($count)",
                            fontWeight = if (selectedTab == tab) FontWeight.Bold else FontWeight.Normal,
                            fontSize = 13.sp
                        )
                    },
                    modifier = Modifier.tvFocusable(cornerRadius = 8.dp, onClick = { viewModel.selectTab(tab) })
                )
            }
        }

        when (selectedTab) {
            LibraryTab.HISTORY -> {
                if (historyList.isEmpty()) {
                    EmptyStateView(
                        icon = Icons.Default.Inbox,
                        title = "История пуста",
                        subtitle = "Здесь появятся просмотренные вами серии"
                    )
                } else {
                    Box(modifier = Modifier.fillMaxSize()) {
                        LazyColumn(
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxSize()
                        ) {
                            item {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.End
                                ) {
                                    TextButton(onClick = { viewModel.clearHistory() }) {
                                        Icon(Icons.Default.Delete, contentDescription = null, tint = DangerColor, modifier = Modifier.size(16.dp))
                                        Spacer(modifier = Modifier.width(4.dp))
                                        Text("Очистить историю", color = DangerColor, fontSize = 12.sp)
                                    }
                                }
                            }
                            items(historyList, key = { it.id }) { item ->
                                HistoryRowItem(item = item, onClick = { onAnimeClick(item.animeId) })
                            }
                        }
                    }
                }
            }
            else -> {
                val currentList = when (selectedTab) {
                    LibraryTab.WATCHING -> watchingList
                    LibraryTab.COMPLETED -> completedList
                    LibraryTab.PLANNED -> plannedList
                    LibraryTab.ON_HOLD -> onHoldList
                    LibraryTab.DROPPED -> droppedList
                    LibraryTab.FAVORITES -> favoritesList
                    else -> emptyList()
                }

                if (currentList.isEmpty()) {
                    EmptyStateView(
                        icon = Icons.Default.Inbox,
                        title = "Список пуст",
                        subtitle = "Добавьте аниме на странице тайтла"
                    )
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 135.dp),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(currentList, key = { it.animeId }) { entry ->
                            val fakeAnime = Anime(
                                id = entry.animeId,
                                title = AnimeTitle(russian = entry.title),
                                coverImage = AnimeCoverImage(large = entry.coverUrl),
                                episodes = entry.episodeCount
                            )
                            PosterCard(anime = fakeAnime, onClick = { onAnimeClick(entry.animeId) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun HistoryRowItem(
    item: WatchHistoryItem,
    onClick: () -> Unit
) {
    val dateStr = remember(item.watchedAt) {
        val sdf = SimpleDateFormat("dd MMM, HH:mm", Locale.getDefault())
        sdf.format(Date(item.watchedAt))
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(SurfaceDark)
            .clickable { onClick() }
            .tvFocusable(cornerRadius = 12.dp, onClick = onClick)
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(45.dp, 60.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(SurfaceElevatedDark)
        ) {
            AsyncImage(
                model = item.coverUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = item.title,
                color = TextPrimaryDark,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = "Серия ${item.episode}",
                color = DefaultAccent,
                fontWeight = FontWeight.Medium,
                fontSize = 12.sp
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = dateStr,
                color = TextSecondaryDark,
                fontSize = 11.sp
            )
        }
    }
}
