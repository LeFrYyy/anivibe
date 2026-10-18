package com.anivibe.app.data.model

import kotlinx.serialization.Serializable

@Serializable
enum class LibraryStatus(val key: String, val title: String) {
    WATCHING("watching", "Смотрю"),
    COMPLETED("completed", "Просмотрено"),
    PLANNED("planned", "Запланировано"),
    ON_HOLD("onHold", "Отложено"),
    DROPPED("dropped", "Брошено");

    companion object {
        fun fromKey(key: String?): LibraryStatus? {
            return entries.firstOrNull { it.key.equals(key, ignoreCase = true) }
        }
    }
}

@Serializable
data class LibraryEntry(
    val animeId: Int,
    val title: String,
    val coverUrl: String? = null,
    val episodeCount: Int? = null,
    val status: LibraryStatus? = null,
    val isFavorite: Boolean = false,
    val lastEpisode: Int? = null,
    val updatedAt: Long = System.currentTimeMillis(),
    val isDeleted: Boolean = false
) {
    val isEmpty: Boolean
        get() = status == null && !isFavorite
}

@Serializable
data class WatchProgress(
    val animeId: Int,
    val episode: Int,
    val sourceKey: String? = null,
    val positionSeconds: Double,
    val durationSeconds: Double,
    val updatedAt: Long = System.currentTimeMillis()
) {
    val fraction: Double
        get() = if (durationSeconds > 0) (positionSeconds / durationSeconds).coerceIn(0.0, 1.0) else 0.0

    val percent: Int
        get() = (fraction * 100).toInt()

    val isFinished: Boolean
        get() = fraction >= 0.90
}

@Serializable
data class WatchHistoryItem(
    val id: String, // UUID
    val animeId: Int,
    val title: String,
    val coverUrl: String? = null,
    val episode: Int,
    val watchedAt: Long = System.currentTimeMillis(),
    val deletedAt: Long? = null
)

@Serializable
data class ContinueWatchingItem(
    val animeId: Int,
    val title: String,
    val coverUrl: String?,
    val episode: Int,
    val positionSeconds: Double,
    val durationSeconds: Double,
    val sourceKey: String? = null
) {
    val percent: Int
        get() = if (durationSeconds > 0) ((positionSeconds / durationSeconds) * 100).toInt().coerceIn(0, 100) else 0
}
