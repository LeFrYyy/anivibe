package com.anivibe.app.ui.screens.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.anivibe.app.data.model.AiredEpisode
import com.anivibe.app.data.model.Anime
import com.anivibe.app.data.model.AnimeCollection
import com.anivibe.app.data.model.ContinueWatchingItem
import com.anivibe.app.data.remote.anilist.AniListService
import com.anivibe.app.data.repository.CatalogRepository
import com.anivibe.app.data.repository.LibraryRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed class HomeUiState {
    object Loading : HomeUiState()
    data class Success(
        val trending: List<Anime>,
        val seasonal: List<Anime>,
        val popular: List<Anime>,
        val recent: List<Anime>,
        val recentEpisodes: List<AiredEpisode>,
        val recommendations: List<Anime> = emptyList()
    ) : HomeUiState()
    data class Error(val message: String) : HomeUiState()
}

class HomeViewModel(
    private val catalogRepository: CatalogRepository,
    private val libraryRepository: LibraryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow<HomeUiState>(HomeUiState.Loading)
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    val continueWatching: StateFlow<List<ContinueWatchingItem>> = libraryRepository
        .observeContinueWatching()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val collections: StateFlow<List<AnimeCollection>> = libraryRepository
        .observeCollections()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        loadFeed()
    }

    fun loadFeed() {
        viewModelScope.launch {
            _uiState.value = HomeUiState.Loading
            try {
                val feed = catalogRepository.getHomeFeed()
                val recentEpisodes = try {
                    catalogRepository.getRecentEpisodes()
                } catch (e: Exception) {
                    emptyList()
                }

                // If continue watching has items, load recommendations for the first one
                val recs = try {
                    val firstItem = continueWatching.value.firstOrNull()
                    if (firstItem != null) {
                        catalogRepository.getDetails(firstItem.animeId).recommendations
                    } else emptyList()
                } catch (e: Exception) {
                    emptyList()
                }

                _uiState.value = HomeUiState.Success(
                    trending = feed.trending,
                    seasonal = feed.seasonal,
                    popular = feed.popular,
                    recent = feed.recent,
                    recentEpisodes = recentEpisodes,
                    recommendations = recs
                )
            } catch (e: Exception) {
                _uiState.value = HomeUiState.Error(e.message ?: "Не удалось загрузить данные")
            }
        }
    }
}
