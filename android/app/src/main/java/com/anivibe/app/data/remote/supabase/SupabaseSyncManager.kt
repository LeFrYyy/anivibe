package com.anivibe.app.data.remote.supabase

import com.anivibe.app.data.local.AnivibeDatabase
import com.anivibe.app.data.local.entity.CollectionEntity
import com.anivibe.app.data.local.entity.LibraryEntryEntity
import com.anivibe.app.data.local.entity.WatchHistoryEntity
import com.anivibe.app.data.local.entity.WatchProgressEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class SupabaseSyncManager(
    private val database: AnivibeDatabase,
    private val authService: SupabaseAuthService,
    private val restService: SupabaseRestService
) {
    private val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    private fun parseIso(iso: String): Long {
        return try {
            isoFormat.parse(iso)?.time ?: System.currentTimeMillis()
        } catch (e: Exception) {
            System.currentTimeMillis()
        }
    }

    private fun formatIso(millis: Long): String {
        return isoFormat.format(Date(millis))
    }

    suspend fun sync(): Boolean = withContext(Dispatchers.IO) {
        val user = authService.currentUser.value ?: return@withContext false
        val token = authService.getAccessToken() ?: return@withContext false

        try {
            // 1. PUSH LOCAL DATA TO SUPABASE
            val localEntries = database.libraryDao().getAllEntries().first()
            if (localEntries.isNotEmpty()) {
                val entryRows = localEntries.map {
                    LibraryEntryRow(
                        userId = user.id,
                        animeId = it.animeId,
                        title = it.title,
                        coverUrl = it.coverUrl,
                        episodeCount = it.episodeCount,
                        status = it.status,
                        isFavorite = it.isFavorite,
                        lastEpisode = it.lastEpisode,
                        isDeleted = it.isDeleted,
                        updatedAt = formatIso(it.updatedAt)
                    )
                }
                restService.upsertTable("library_entries", "user_id,anime_id", entryRows, token)
            }

            val localProgress = database.watchProgressDao().observeRecentProgress().first()
            if (localProgress.isNotEmpty()) {
                val progressRows = localProgress.map {
                    WatchProgressRow(
                        userId = user.id,
                        animeId = it.animeId,
                        episode = it.episode,
                        sourceKey = it.sourceKey,
                        positionSeconds = it.positionSeconds,
                        durationSeconds = it.durationSeconds,
                        updatedAt = formatIso(it.updatedAt)
                    )
                }
                restService.upsertTable("watch_progress", "user_id,anime_id,episode,source_key", progressRows, token)
            }

            val localHistory = database.watchHistoryDao().observeHistory().first()
            if (localHistory.isNotEmpty()) {
                val historyRows = localHistory.map {
                    WatchHistoryRow(
                        id = it.id,
                        userId = user.id,
                        animeId = it.animeId,
                        title = it.title,
                        coverUrl = it.coverUrl,
                        episode = it.episode,
                        watchedAt = formatIso(it.watchedAt),
                        deletedAt = it.deletedAt?.let { d -> formatIso(d) }
                    )
                }
                restService.upsertTable("watch_history", "id", historyRows, token)
            }

            val localCollections = database.collectionDao().observeCollections().first()
            if (localCollections.isNotEmpty()) {
                val collectionRows = localCollections.map {
                    val ids = try {
                        Json.decodeFromString<List<Int>>(it.animeIdsJson)
                    } catch (e: Exception) {
                        emptyList()
                    }
                    CollectionRow(
                        id = it.id,
                        userId = user.id,
                        name = it.name,
                        emoji = it.emoji,
                        animeIds = ids,
                        displayOrder = it.displayOrder,
                        updatedAt = formatIso(it.updatedAt)
                    )
                }
                restService.upsertTable("account_collections", "user_id,id", collectionRows, token)
            }

            // 2. PULL REMOTE UPDATES FROM SUPABASE
            val remoteEntries: List<LibraryEntryRow> = restService.fetchTable("library_entries", token)
            val updatedEntries = remoteEntries.map { row ->
                LibraryEntryEntity(
                    animeId = row.animeId,
                    title = row.title,
                    coverUrl = row.coverUrl,
                    episodeCount = row.episodeCount,
                    status = row.status,
                    isFavorite = row.isFavorite,
                    lastEpisode = row.lastEpisode,
                    updatedAt = parseIso(row.updatedAt),
                    isDeleted = row.isDeleted
                )
            }
            if (updatedEntries.isNotEmpty()) {
                database.libraryDao().upsertEntries(updatedEntries)
            }

            val remoteProgress: List<WatchProgressRow> = restService.fetchTable("watch_progress", token)
            val updatedProgress = remoteProgress.map { row ->
                WatchProgressEntity(
                    animeId = row.animeId,
                    episode = row.episode,
                    sourceKey = row.sourceKey,
                    positionSeconds = row.positionSeconds,
                    durationSeconds = row.durationSeconds,
                    updatedAt = parseIso(row.updatedAt)
                )
            }
            if (updatedProgress.isNotEmpty()) {
                database.watchProgressDao().upsertAll(updatedProgress)
            }

            val remoteHistory: List<WatchHistoryRow> = restService.fetchTable("watch_history", token)
            val updatedHistory = remoteHistory.map { row ->
                WatchHistoryEntity(
                    id = row.id,
                    animeId = row.animeId,
                    title = row.title,
                    coverUrl = row.coverUrl,
                    episode = row.episode,
                    watchedAt = parseIso(row.watchedAt),
                    deletedAt = row.deletedAt?.let { parseIso(it) }
                )
            }
            if (updatedHistory.isNotEmpty()) {
                database.watchHistoryDao().insertAll(updatedHistory)
            }

            val remoteCollections: List<CollectionRow> = restService.fetchTable("account_collections", token)
            val updatedCollections = remoteCollections.map { row ->
                CollectionEntity(
                    id = row.id,
                    name = row.name,
                    emoji = row.emoji,
                    animeIdsJson = Json.encodeToString(row.animeIds),
                    displayOrder = row.displayOrder,
                    updatedAt = parseIso(row.updatedAt)
                )
            }
            if (updatedCollections.isNotEmpty()) {
                database.collectionDao().upsertAll(updatedCollections)
            }

            true
        } catch (e: Exception) {
            false
        }
    }
}
