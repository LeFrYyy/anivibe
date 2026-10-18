package com.anivibe.app.ui.screens.details

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.anivibe.app.data.model.*
import com.anivibe.app.data.remote.anilibria.AnilibriaRelease
import com.anivibe.app.data.repository.CatalogRepository
import com.anivibe.app.data.repository.LibraryRepository
import com.anivibe.app.data.repository.VideoSourceRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed class DetailsUiState {
    object Loading : DetailsUiState()
    data class Success(
        val anime: Anime,
        val kodikMaterials: List<KodikMaterialDto>,
        val selectedMaterial: KodikMaterialDto?,
        val anilibriaRelease: AnilibriaRelease?,
        val episodes: List<ProviderEpisode>
    ) : DetailsUiState()
    data class Error(val message: String) : DetailsUiState()
}

class AnimeDetailsViewModel(
    private val animeId: Int,
    private val catalogRepository: CatalogRepository,
    private val videoSourceRepository: VideoSourceRepository,
    private val libraryRepository: LibraryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow<DetailsUiState>(DetailsUiState.Loading)
    val uiState: StateFlow<DetailsUiState> = _uiState.asStateFlow()

    val libraryEntry: StateFlow<LibraryEntry?> = libraryRepository
        .observeEntry(animeId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val watchProgress: StateFlow<List<WatchProgress>> = libraryRepository
        .observeProgressForAnime(animeId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        loadDetails()
    }

    fun loadDetails() {
        viewModelScope.launch {
            _uiState.value = DetailsUiState.Loading
            try {
                val anime = catalogRepository.getDetails(animeId)
                val sources = try {
                    videoSourceRepository.findSources(anime)
                } catch (e: Exception) {
                    VideoSourceRepository.AnimeSources(emptyList(), null)
                }

                val primaryMaterial = sources.kodikMaterials.firstOrNull()
                val episodes = videoSourceRepository.getEpisodes(primaryMaterial, sources.anilibriaRelease)

                _uiState.value = DetailsUiState.Success(
                    anime = anime,
                    kodikMaterials = sources.kodikMaterials,
                    selectedMaterial = primaryMaterial,
                    anilibriaRelease = sources.anilibriaRelease,
                    episodes = episodes
                )
            } catch (e: Exception) {
                _uiState.value = DetailsUiState.Error(e.message ?: "Не удалось загрузить данные аниме")
            }
        }
    }

    fun selectTranslation(material: KodikMaterialDto) {
        val current = _uiState.value as? DetailsUiState.Success ?: return
        viewModelScope.launch {
            val episodes = videoSourceRepository.getEpisodes(material, current.anilibriaRelease)
            _uiState.value = current.copy(
                selectedMaterial = material,
                episodes = episodes
            )
        }
    }

    fun setStatus(status: LibraryStatus?) {
        val current = _uiState.value as? DetailsUiState.Success ?: return
        viewModelScope.launch {
            libraryRepository.setStatus(current.anime, status)
        }
    }

    fun toggleFavorite() {
        val current = _uiState.value as? DetailsUiState.Success ?: return
        viewModelScope.launch {
            libraryRepository.toggleFavorite(current.anime)
        }
    }
}
