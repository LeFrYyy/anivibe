package com.anivibe.app.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.anivibe.app.data.model.AnimeCollection
import com.anivibe.app.data.model.LibraryEntry
import com.anivibe.app.data.model.LibraryStatus
import com.anivibe.app.data.model.WatchHistoryItem
import com.anivibe.app.data.model.WatchProgress
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Entity(tableName = "library_entries")
data class LibraryEntryEntity(
    @PrimaryKey val animeId: Int,
    val title: String,
    val coverUrl: String?,
    val episodeCount: Int?,
    val status: String?, // watching, completed, planned, onHold, dropped
    val isFavorite: Boolean,
    val lastEpisode: Int?,
    val updatedAt: Long,
    val isDeleted: Boolean
) {
    fun toModel(): LibraryEntry = LibraryEntry(
        animeId = animeId,
        title = title,
        coverUrl = coverUrl,
        episodeCount = episodeCount,
        status = LibraryStatus.fromKey(status),
        isFavorite = isFavorite,
        lastEpisode = lastEpisode,
        updatedAt = updatedAt,
        isDeleted = isDeleted
    )

    companion object {
        fun fromModel(model: LibraryEntry): LibraryEntryEntity = LibraryEntryEntity(
            animeId = model.animeId,
            title = model.title,
            coverUrl = model.coverUrl,
            episodeCount = model.episodeCount,
            status = model.status?.key,
            isFavorite = model.isFavorite,
            lastEpisode = model.lastEpisode,
            updatedAt = model.updatedAt,
            isDeleted = model.isDeleted
        )
    }
}

@Entity(
    tableName = "watch_progress",
    primaryKeys = ["animeId", "episode", "sourceKey"]
)
data class WatchProgressEntity(
    val animeId: Int,
    val episode: Int,
    val sourceKey: String = "",
    val positionSeconds: Double,
    val durationSeconds: Double,
    val updatedAt: Long
) {
    fun toModel(): WatchProgress = WatchProgress(
        animeId = animeId,
        episode = episode,
        sourceKey = sourceKey.ifEmpty { null },
        positionSeconds = positionSeconds,
        durationSeconds = durationSeconds,
        updatedAt = updatedAt
    )

    companion object {
        fun fromModel(model: WatchProgress): WatchProgressEntity = WatchProgressEntity(
            animeId = model.animeId,
            episode = model.episode,
            sourceKey = model.sourceKey ?: "",
            positionSeconds = model.positionSeconds,
            durationSeconds = model.durationSeconds,
            updatedAt = model.updatedAt
        )
    }
}

@Entity(tableName = "watch_history")
data class WatchHistoryEntity(
    @PrimaryKey val id: String,
    val animeId: Int,
    val title: String,
    val coverUrl: String?,
    val episode: Int,
    val watchedAt: Long,
    val deletedAt: Long?
) {
    fun toModel(): WatchHistoryItem = WatchHistoryItem(
        id = id,
        animeId = animeId,
        title = title,
        coverUrl = coverUrl,
        episode = episode,
        watchedAt = watchedAt,
        deletedAt = deletedAt
    )

    companion object {
        fun fromModel(model: WatchHistoryItem): WatchHistoryEntity = WatchHistoryEntity(
            id = model.id,
            animeId = model.animeId,
            title = model.title,
            coverUrl = model.coverUrl,
            episode = model.episode,
            watchedAt = model.watchedAt,
            deletedAt = model.deletedAt
        )
    }
}

@Entity(tableName = "account_collections")
data class CollectionEntity(
    @PrimaryKey val id: String,
    val name: String,
    val emoji: String,
    val animeIdsJson: String,
    val displayOrder: Int,
    val updatedAt: Long
) {
    fun toModel(): AnimeCollection {
        val ids = try {
            Json.decodeFromString<List<Int>>(animeIdsJson)
        } catch (e: Exception) {
            emptyList()
        }
        return AnimeCollection(
            id = id,
            name = name,
            emoji = emoji,
            animeIds = ids,
            displayOrder = displayOrder,
            updatedAt = updatedAt
        )
    }

    companion object {
        fun fromModel(model: AnimeCollection): CollectionEntity = CollectionEntity(
            id = model.id,
            name = model.name,
            emoji = model.emoji,
            animeIdsJson = Json.encodeToString(model.animeIds),
            displayOrder = model.displayOrder,
            updatedAt = model.updatedAt
        )
    }
}
