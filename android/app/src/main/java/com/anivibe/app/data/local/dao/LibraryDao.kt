package com.anivibe.app.data.local.dao

import androidx.room.*
import com.anivibe.app.data.local.entity.LibraryEntryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface LibraryDao {

    @Query("SELECT * FROM library_entries WHERE isDeleted = 0 ORDER BY updatedAt DESC")
    fun getAllEntries(): Flow<List<LibraryEntryEntity>>

    @Query("SELECT * FROM library_entries WHERE isDeleted = 0 AND status = :status ORDER BY updatedAt DESC")
    fun getEntriesByStatus(status: String): Flow<List<LibraryEntryEntity>>

    @Query("SELECT * FROM library_entries WHERE isDeleted = 0 AND isFavorite = 1 ORDER BY updatedAt DESC")
    fun getFavorites(): Flow<List<LibraryEntryEntity>>

    @Query("SELECT * FROM library_entries WHERE animeId = :animeId LIMIT 1")
    suspend fun getEntry(animeId: Int): LibraryEntryEntity?

    @Query("SELECT * FROM library_entries WHERE animeId = :animeId LIMIT 1")
    fun observeEntry(animeId: Int): Flow<LibraryEntryEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertEntry(entry: LibraryEntryEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertEntries(entries: List<LibraryEntryEntity>)

    @Query("UPDATE library_entries SET isDeleted = 1, updatedAt = :timestamp WHERE animeId = :animeId")
    suspend fun softDelete(animeId: Int, timestamp: Long = System.currentTimeMillis())

    @Query("SELECT COUNT(*) FROM library_entries WHERE isDeleted = 0 AND status = :status")
    suspend fun countByStatus(status: String): Int

    @Query("SELECT COUNT(*) FROM library_entries WHERE isDeleted = 0 AND isFavorite = 1")
    suspend fun countFavorites(): Int
}
