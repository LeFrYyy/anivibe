package com.anivibe.app.ui.screens.catalog

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.anivibe.app.data.model.*
import com.anivibe.app.data.repository.CatalogRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CatalogFilters(
    val query: String = "",
    val selectedGenres: Set<String> = emptySet(),
    val season: AnimeSeason? = null,
    val year: Int? = null,
    val format: AnimeFormat? = null,
    val status: AnimeStatus? = null,
    val sort: AnimeSort = AnimeSort.POPULARITY_DESC
)

sealed class CatalogUiState {
    object Loading : CatalogUiState()
    data class Content(
        val items: List<Anime>,
        val hasNextPage: Boolean,
        val isLoadingMore: Boolean = false
    ) : CatalogUiState()
    data class Error(val message: String) : CatalogUiState()
}

class CatalogViewModel(
    private val catalogRepository: CatalogRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow<CatalogUiState>(CatalogUiState.Loading)
    val uiState: StateFlow<CatalogUiState> = _uiState.asStateFlow()

    private val _filters = MutableStateFlow(CatalogFilters())
    val filters: StateFlow<CatalogFilters> = _filters.asStateFlow()

    private var currentPage = 1
    private var searchJob: Job? = null

    val availableGenres = listOf(
        "Action", "Adventure", "Comedy", "Drama", "Fantasy",
        "Horror", "Mystery", "Psychological", "Romance", "Sci-Fi",
        "Slice of Life", "Sports", "Supernatural", "Thriller"
    )

    init {
        loadCatalog(reset = true)
    }

    fun onQueryChange(newQuery: String) {
        _filters.value = _filters.value.copy(query = newQuery)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(400) // Debounce
            loadCatalog(reset = true)
        }
    }

    fun updateFilters(newFilters: CatalogFilters) {
        _filters.value = newFilters
        loadCatalog(reset = true)
    }

    fun loadMore() {
        val current = _uiState.value as? CatalogUiState.Content ?: return
        if (current.isLoadingMore || !current.hasNextPage) return

        viewModelScope.launch {
            _uiState.value = current.copy(isLoadingMore = true)
            try {
                val f = _filters.value
                val nextPage = currentPage + 1
                val result = catalogRepository.search(
                    query = f.query.ifBlank { null },
                    page = nextPage,
                    genres = f.selectedGenres.toList().ifEmpty { null },
                    year = f.year,
                    season = f.season,
                    status = f.status,
                    format = f.format,
                    sort = f.sort
                )
                currentPage = nextPage
                _uiState.value = CatalogUiState.Content(
                    items = current.items + result.items,
                    hasNextPage = result.hasNextPage,
                    isLoadingMore = false
                )
            } catch (e: Exception) {
                _uiState.value = current.copy(isLoadingMore = false)
            }
        }
    }

    fun loadCatalog(reset: Boolean = false) {
        if (reset) {
            currentPage = 1
            _uiState.value = CatalogUiState.Loading
        }
        viewModelScope.launch {
            try {
                val f = _filters.value
                val result = catalogRepository.search(
                    query = f.query.ifBlank { null },
                    page = currentPage,
                    genres = f.selectedGenres.toList().ifEmpty { null },
                    year = f.year,
                    season = f.season,
                    status = f.status,
                    format = f.format,
                    sort = f.sort
                )
                _uiState.value = CatalogUiState.Content(
                    items = result.items,
                    hasNextPage = result.hasNextPage,
                    isLoadingMore = false
                )
            } catch (e: Exception) {
                _uiState.value = CatalogUiState.Error(e.message ?: "Ошибка загрузки каталога")
            }
        }
    }
}
