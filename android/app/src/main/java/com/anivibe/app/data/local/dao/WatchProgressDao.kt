package com.anivibe.app.data.local.dao

import androidx.room.*
import com.anivibe.app.data.local.entity.WatchProgressEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface WatchProgressDao {

    @Query("SELECT * FROM watch_progress WHERE animeId = :animeId AND episode = :episode AND sourceKey = :sourceKey LIMIT 1")
    suspend fun getProgress(animeId: Int, episode: Int, sourceKey: String = ""): WatchProgressEntity?

    @Query("SELECT * FROM watch_progress WHERE animeId = :animeId ORDER BY updatedAt DESC")
    fun observeProgressForAnime(animeId: Int): Flow<List<WatchProgressEntity>>

    @Query("SELECT * FROM watch_progress WHERE animeId = :animeId ORDER BY updatedAt DESC")
    suspend fun getProgressForAnime(animeId: Int): List<WatchProgressEntity>

    @Query("SELECT * FROM watch_progress ORDER BY updatedAt DESC LIMIT 20")
    fun observeRecentProgress(): Flow<List<WatchProgressEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProgress(progress: WatchProgressEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(list: List<WatchProgressEntity>)
}
