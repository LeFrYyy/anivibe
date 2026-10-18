package com.anivibe.app.data.repository

import com.anivibe.app.data.local.AnivibeDatabase
import com.anivibe.app.data.local.entity.CollectionEntity
import com.anivibe.app.data.local.entity.LibraryEntryEntity
import com.anivibe.app.data.local.entity.WatchHistoryEntity
import com.anivibe.app.data.local.entity.WatchProgressEntity
import com.anivibe.app.data.model.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.util.UUID

class LibraryRepository(
    private val database: AnivibeDatabase
) {
    fun getAllEntries(): Flow<List<LibraryEntry>> {
        return database.libraryDao().getAllEntries().map { list -> list.map { it.toModel() } }
    }

    fun getEntriesByStatus(status: LibraryStatus): Flow<List<LibraryEntry>> {
        return database.libraryDao().getEntriesByStatus(status.key).map { list -> list.map { it.toModel() } }
    }

    fun getFavorites(): Flow<List<LibraryEntry>> {
        return database.libraryDao().getFavorites().map { list -> list.map { it.toModel() } }
    }

    fun observeEntry(animeId: Int): Flow<LibraryEntry?> {
        return database.libraryDao().observeEntry(animeId).map { it?.toModel() }
    }

    fun observeProgressForAnime(animeId: Int): Flow<List<WatchProgress>> {
        return database.watchProgressDao().observeProgressForAnime(animeId).map { list -> list.map { it.toModel() } }
    }

    fun observeContinueWatching(): Flow<List<ContinueWatchingItem>> {
        return combine(
            database.watchProgressDao().observeRecentProgress(),
            database.libraryDao().getAllEntries()
        ) { progressList, entries ->
            val entryMap = entries.associateBy { it.animeId }
            progressList
                .filter { it.positionSeconds > 10 }
                .distinctBy { it.animeId }
                .map { prog ->
                    val entry = entryMap[prog.animeId]
                    ContinueWatchingItem(
                        animeId = prog.animeId,
                        title = entry?.title ?: "Аниме #${prog.animeId}",
                        coverUrl = entry?.coverUrl,
                        episode = prog.episode,
                        positionSeconds = prog.positionSeconds,
                        durationSeconds = prog.durationSeconds,
                        sourceKey = prog.sourceKey.ifEmpty { null }
                    )
                }
        }
    }

    fun observeHistory(): Flow<List<WatchHistoryItem>> {
        return database.watchHistoryDao().observeHistory().map { list -> list.map { it.toModel() } }
    }

    fun observeCollections(): Flow<List<AnimeCollection>> {
        return database.collectionDao().observeCollections().map { list -> list.map { it.toModel() } }
    }

    suspend fun setStatus(anime: Anime, status: LibraryStatus?) {
        val existing = database.libraryDao().getEntry(anime.id)
        val now = System.currentTimeMillis()
        val updated = if (existing != null) {
            existing.copy(
                status = status?.key,
                updatedAt = now,
                isDeleted = false
            )
        } else {
            LibraryEntryEntity(
                animeId = anime.id,
                title = anime.displayTitle,
                coverUrl = anime.coverImage?.bestUrl,
                episodeCount = anime.episodes,
                status = status?.key,
                isFavorite = false,
                lastEpisode = null,
                updatedAt = now,
                isDeleted = false
            )
        }
        database.libraryDao().upsertEntry(updated)
    }

    suspend fun toggleFavorite(anime: Anime) {
        val existing = database.libraryDao().getEntry(anime.id)
        val now = System.currentTimeMillis()
        val updated = if (existing != null) {
            existing.copy(
                isFavorite = !existing.isFavorite,
                updatedAt = now,
                isDeleted = false
            )
        } else {
            LibraryEntryEntity(
                animeId = anime.id,
                title = anime.displayTitle,
                coverUrl = anime.coverImage?.bestUrl,
                episodeCount = anime.episodes,
                status = null,
                isFavorite = true,
                lastEpisode = null,
                updatedAt = now,
                isDeleted = false
            )
        }
        database.libraryDao().upsertEntry(updated)
    }

    suspend fun saveProgress(
        animeId: Int,
        episode: Int,
        sourceKey: String?,
        positionSeconds: Double,
        durationSeconds: Double
    ) {
        val now = System.currentTimeMillis()
        database.watchProgressDao().upsertProgress(
            WatchProgressEntity(
                animeId = animeId,
                episode = episode,
                sourceKey = sourceKey ?: "",
                positionSeconds = positionSeconds,
                durationSeconds = durationSeconds,
                updatedAt = now
            )
        )
        // Also update lastEpisode in library entry if exists
        val entry = database.libraryDao().getEntry(animeId)
        if (entry != null) {
            database.libraryDao().upsertEntry(entry.copy(lastEpisode = episode, updatedAt = now))
        }
    }

    suspend fun addHistory(anime: Anime, episode: Int) {
        val now = System.currentTimeMillis()
        database.watchHistoryDao().insertHistory(
            WatchHistoryEntity(
                id = UUID.randomUUID().toString(),
                animeId = anime.id,
                title = anime.displayTitle,
                coverUrl = anime.coverImage?.bestUrl,
                episode = episode,
                watchedAt = now,
                deletedAt = null
            )
        )
    }

    suspend fun clearHistory() {
        database.watchHistoryDao().clearHistory()
    }

    suspend fun createCollection(name: String, emoji: String = "📁") {
        val collection = AnimeCollection(
            id = UUID.randomUUID().toString(),
            name = name,
            emoji = emoji
        )
        database.collectionDao().upsertCollection(CollectionEntity.fromModel(collection))
    }

    suspend fun deleteCollection(id: String) {
        database.collectionDao().deleteCollection(id)
    }

    suspend fun getStats(): UserStats {
        val watching = database.libraryDao().countByStatus("watching")
        val completed = database.libraryDao().countByStatus("completed")
        val planned = database.libraryDao().countByStatus("planned")
        val onHold = database.libraryDao().countByStatus("onHold")
        val dropped = database.libraryDao().countByStatus("dropped")
        val favorites = database.libraryDao().countFavorites()
        val total = watching + completed + planned + onHold + dropped
        return UserStats(watching, completed, planned, onHold, dropped, favorites, total)
    }
}
