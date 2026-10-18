package com.anivibe.app.data.local.dao

import androidx.room.*
import com.anivibe.app.data.local.entity.WatchHistoryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface WatchHistoryDao {

    @Query("SELECT * FROM watch_history WHERE deletedAt IS NULL ORDER BY watchedAt DESC")
    fun observeHistory(): Flow<List<WatchHistoryEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertHistory(item: WatchHistoryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(items: List<WatchHistoryEntity>)

    @Query("UPDATE watch_history SET deletedAt = :now WHERE id = :id")
    suspend fun softDelete(id: String, now: Long = System.currentTimeMillis())

    @Query("UPDATE watch_history SET deletedAt = :now WHERE deletedAt IS NULL")
    suspend fun clearHistory(now: Long = System.currentTimeMillis())
}
