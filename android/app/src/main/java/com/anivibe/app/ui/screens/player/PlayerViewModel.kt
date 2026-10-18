package com.anivibe.app.ui.screens.player

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.anivibe.app.data.model.Anime
import com.anivibe.app.data.model.KodikStream
import com.anivibe.app.data.model.ProviderEpisode
import com.anivibe.app.data.repository.CatalogRepository
import com.anivibe.app.data.repository.LibraryRepository
import com.anivibe.app.data.repository.VideoSourceRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class PlayerState(
    val anime: Anime? = null,
    val currentEpisodeNumber: Int = 1,
    val episodes: List<ProviderEpisode> = emptyList(),
    val currentEpisode: ProviderEpisode? = null,
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = false,
    val currentPosition: Long = 0,
    val duration: Long = 0,
    val availableQualities: List<KodikStream> = emptyList(),
    val selectedQuality: Int? = null,
    val useWebPlayerFallback: Boolean = false,
    val error: String? = null
)

class PlayerViewModel(
    private val animeId: Int,
    private val initialEpisode: Int,
    private val initialSourceKey: String?,
    private val context: Context,
    private val catalogRepository: CatalogRepository,
    private val videoSourceRepository: VideoSourceRepository,
    private val libraryRepository: LibraryRepository
) : ViewModel() {

    private val _state = MutableStateFlow(PlayerState(currentEpisodeNumber = initialEpisode))
    val state: StateFlow<PlayerState> = _state.asStateFlow()

    var exoPlayer: ExoPlayer? = null
        private set

    private var progressTrackerJob: Job? = null
    private var lastSavedPosition = 0L

    init {
        initPlayer()
        loadAnimeAndEpisodes()
    }

    private fun initPlayer() {
        val player = ExoPlayer.Builder(context).build().apply {
            playWhenReady = true
            addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    _state.value = _state.value.copy(isPlaying = isPlaying)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_BUFFERING -> _state.value = _state.value.copy(isBuffering = true)
                        Player.STATE_READY -> {
                            _state.value = _state.value.copy(
                                isBuffering = false,
                                duration = duration.coerceAtLeast(0)
                            )
                        }
                        Player.STATE_ENDED -> {
                            saveCurrentProgress()
                            playNextEpisode()
                        }
                        else -> _state.value = _state.value.copy(isBuffering = false)
                    }
                }
            })
        }
        exoPlayer = player
        startProgressTracker()
    }

    private fun loadAnimeAndEpisodes() {
        viewModelScope.launch {
            try {
                val anime = catalogRepository.getDetails(animeId)
                val sources = videoSourceRepository.findSources(anime)
                val primaryMat = sources.kodikMaterials.firstOrNull()
                val epList = videoSourceRepository.getEpisodes(primaryMat, sources.anilibriaRelease)

                _state.value = _state.value.copy(
                    anime = anime,
                    episodes = epList
                )

                playEpisode(initialEpisode, initialSourceKey)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message ?: "Ошибка загрузки источников")
            }
        }
    }

    fun playEpisode(episodeNumber: Int, sourceKey: String? = null) {
        viewModelScope.launch {
            val epItem = _state.value.episodes.firstOrNull { it.episodeNumber == episodeNumber }
                ?: _state.value.episodes.firstOrNull()
                ?: return@launch

            _state.value = _state.value.copy(
                currentEpisodeNumber = epItem.episodeNumber,
                currentEpisode = epItem,
                isBuffering = true,
                useWebPlayerFallback = false
            )

            // Resolve direct stream
            val resolved = videoSourceRepository.resolveStream(epItem)
            _state.value = _state.value.copy(
                currentEpisode = resolved,
                availableQualities = resolved.availableQualities,
                selectedQuality = resolved.availableQualities.firstOrNull()?.quality
            )

            val streamUrl = resolved.hlsUrl ?: resolved.mp4Url
            if (streamUrl != null) {
                val mediaItem = MediaItem.fromUri(streamUrl)
                exoPlayer?.setMediaItem(mediaItem)
                exoPlayer?.prepare()

                // Check saved progress
                val savedProgress = libraryRepository.observeProgressForAnime(animeId)
                // Resume position if >= 10s
                exoPlayer?.play()
                _state.value.anime?.let { anime ->
                    libraryRepository.addHistory(anime, epItem.episodeNumber)
                }
            } else if (!resolved.webPlayerUrl.isNullOrEmpty()) {
                // Direct stream couldn't be extracted, open in WebKit Kodik player
                _state.value = _state.value.copy(useWebPlayerFallback = true, isBuffering = false)
                _state.value.anime?.let { anime ->
                    libraryRepository.addHistory(anime, epItem.episodeNumber)
                }
            } else {
                _state.value = _state.value.copy(error = "Поток серии недоступен", isBuffering = false)
            }
        }
    }

    fun togglePlayPause() {
        exoPlayer?.let { player ->
            if (player.isPlaying) {
                player.pause()
                saveCurrentProgress()
            } else {
                player.play()
            }
        }
    }

    fun seekRelative(seconds: Int) {
        exoPlayer?.let { player ->
            val target = (player.currentPosition + seconds * 1000).coerceIn(0, player.duration)
            player.seekTo(target)
        }
    }

    fun seekToPosition(positionMs: Long) {
        exoPlayer?.seekTo(positionMs)
    }

    fun selectQuality(quality: Int) {
        val stream = _state.value.availableQualities.firstOrNull { it.quality == quality } ?: return
        val currentPos = exoPlayer?.currentPosition ?: 0L
        val isPlaying = exoPlayer?.isPlaying ?: true

        _state.value = _state.value.copy(selectedQuality = quality)
        val mediaItem = MediaItem.fromUri(stream.url)
        exoPlayer?.setMediaItem(mediaItem, currentPos)
        exoPlayer?.prepare()
        if (isPlaying) exoPlayer?.play()
    }

    fun playNextEpisode() {
        val nextEp = _state.value.currentEpisodeNumber + 1
        if (_state.value.episodes.any { it.episodeNumber == nextEp }) {
            playEpisode(nextEp)
        }
    }

    private fun startProgressTracker() {
        progressTrackerJob = viewModelScope.launch {
            while (isActive) {
                exoPlayer?.let { player ->
                    if (player.isPlaying) {
                        val pos = player.currentPosition
                        val dur = player.duration.coerceAtLeast(0)
                        _state.value = _state.value.copy(
                            currentPosition = pos,
                            duration = dur
                        )

                        // Save progress every 5 seconds
                        if (Math.abs(pos - lastSavedPosition) >= 5000 && dur > 0) {
                            lastSavedPosition = pos
                            saveCurrentProgress()
                        }
                    }
                }
                delay(1000)
            }
        }
    }

    private fun saveCurrentProgress() {
        val pos = exoPlayer?.currentPosition ?: return
        val dur = exoPlayer?.duration ?: return
        if (dur <= 0) return

        viewModelScope.launch {
            libraryRepository.saveProgress(
                animeId = animeId,
                episode = _state.value.currentEpisodeNumber,
                sourceKey = _state.value.currentEpisode?.sourceKey,
                positionSeconds = pos / 1000.0,
                durationSeconds = dur / 1000.0
            )
        }
    }

    override fun onCleared() {
        super.onCleared()
        saveCurrentProgress()
        progressTrackerJob?.cancel()
        exoPlayer?.release()
        exoPlayer = null
    }
}
