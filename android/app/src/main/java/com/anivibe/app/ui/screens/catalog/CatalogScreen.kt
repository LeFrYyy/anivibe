package com.anivibe.app.ui.screens.catalog

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anivibe.app.core.theme.*
import com.anivibe.app.data.model.AnimeFormat
import com.anivibe.app.data.model.AnimeSeason
import com.anivibe.app.data.model.AnimeSort
import com.anivibe.app.data.model.AnimeStatus
import com.anivibe.app.ui.components.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogScreen(
    viewModel: CatalogViewModel,
    onAnimeClick: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val filters by viewModel.filters.collectAsState()
    var showFilterSheet by remember { mutableStateOf(false) }

    val gridState = rememberLazyGridState()

    // Detect when reached near bottom to load more
    val shouldLoadMore = remember {
        derivedStateOf {
            val totalItems = gridState.layoutInfo.totalItemsCount
            val lastVisibleItem = gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            totalItems > 0 && lastVisibleItem >= totalItems - 6
        }
    }

    LaunchedEffect(shouldLoadMore.value) {
        if (shouldLoadMore.value) {
            viewModel.loadMore()
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundDark)
    ) {
        // Search & Filter Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = filters.query,
                onValueChange = { viewModel.onQueryChange(it) },
                placeholder = { Text("Поиск аниме...", color = TextSecondaryDark, fontSize = 14.sp) },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = TextSecondaryDark) },
                trailingIcon = {
                    if (filters.query.isNotEmpty()) {
                        IconButton(onClick = { viewModel.onQueryChange("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear", tint = TextSecondaryDark)
                        }
                    }
                },
                singleLine = true,
                shape = RoundedCornerShape(16.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = SurfaceDark,
                    unfocusedContainerColor = SurfaceDark,
                    focusedBorderColor = DefaultAccent,
                    unfocusedBorderColor = SeparatorDark,
                    focusedTextColor = TextPrimaryDark,
                    unfocusedTextColor = TextPrimaryDark
                ),
                modifier = Modifier
                    .weight(1f)
                    .tvFocusable(cornerRadius = 16.dp)
            )

            Spacer(modifier = Modifier.width(10.dp))

            FilledTonalIconButton(
                onClick = { showFilterSheet = true },
                colors = IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = if (filters.selectedGenres.isNotEmpty() || filters.format != null || filters.status != null) DefaultAccent else SurfaceDark
                ),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier
                    .size(52.dp)
                    .tvFocusable(cornerRadius = 16.dp, onClick = { showFilterSheet = true })
            ) {
                Icon(
                    Icons.Default.FilterList,
                    contentDescription = "Filters",
                    tint = if (filters.selectedGenres.isNotEmpty() || filters.format != null || filters.status != null) Color.Black else TextPrimaryDark
                )
            }
        }

        // Main Catalog Content
        when (val state = uiState) {
            is CatalogUiState.Loading -> LoadingView()
            is CatalogUiState.Error -> ErrorView(
                message = state.message,
                onRetry = { viewModel.loadCatalog(reset = true) }
            )
            is CatalogUiState.Content -> {
                if (state.items.isEmpty()) {
                    EmptyStateView(
                        icon = Icons.Default.Search,
                        title = "Ничего не найдено",
                        subtitle = "Попробуйте изменить поисковый запрос или фильтры"
                    )
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 135.dp),
                        state = gridState,
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(state.items, key = { it.id }) { anime ->
                            PosterCard(
                                anime = anime,
                                onClick = { onAnimeClick(anime.id) },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }

                        if (state.isLoadingMore) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    CircularProgressIndicator(color = DefaultAccent, modifier = Modifier.size(28.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Filter Sheet Modal
    if (showFilterSheet) {
        ModalBottomSheet(
            onDismissRequest = { showFilterSheet = false },
            containerColor = SurfaceDark
        ) {
            FilterSheetContent(
                filters = filters,
                availableGenres = viewModel.availableGenres,
                onApply = { newFilters ->
                    viewModel.updateFilters(newFilters)
                    showFilterSheet = false
                },
                onReset = {
                    viewModel.updateFilters(CatalogFilters(query = filters.query))
                    showFilterSheet = false
                }
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FilterSheetContent(
    filters: CatalogFilters,
    availableGenres: List<String>,
    onApply: (CatalogFilters) -> Unit,
    onReset: () -> Unit
) {
    var selectedGenres by remember { mutableStateOf(filters.selectedGenres) }
    var selectedFormat by remember { mutableStateOf(filters.format) }
    var selectedStatus by remember { mutableStateOf(filters.status) }
    var selectedSort by remember { mutableStateOf(filters.sort) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 12.dp)
            .padding(bottom = 24.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Фильтры каталога", color = TextPrimaryDark, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            TextButton(onClick = onReset) {
                Text("Сбросить", color = DangerColor)
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        Text("Сортировка", color = TextSecondaryDark, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            AnimeSort.entries.forEach { sort ->
                FilterChip(
                    selected = selectedSort == sort,
                    onClick = { selectedSort = sort },
                    label = { Text(sort.displayName) }
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        Text("Формат", color = TextSecondaryDark, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            AnimeFormat.entries.forEach { fmt ->
                FilterChip(
                    selected = selectedFormat == fmt,
                    onClick = { selectedFormat = if (selectedFormat == fmt) null else fmt },
                    label = { Text(fmt.displayName) }
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        Text("Жанры", color = TextSecondaryDark, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(8.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            availableGenres.forEach { genre ->
                val isSelected = selectedGenres.contains(genre)
                FilterChip(
                    selected = isSelected,
                    onClick = {
                        selectedGenres = if (isSelected) selectedGenres - genre else selectedGenres + genre
                    },
                    label = { Text(genre) }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = {
                onApply(
                    filters.copy(
                        selectedGenres = selectedGenres,
                        format = selectedFormat,
                        status = selectedStatus,
                        sort = selectedSort
                    )
                )
            },
            colors = ButtonDefaults.buttonColors(containerColor = DefaultAccent),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp)
        ) {
            Text("Применить фильтры", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 15.sp)
        }
    }
}
