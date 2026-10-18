package com.anivibe.app.data.local.dao

import androidx.room.*
import com.anivibe.app.data.local.entity.CollectionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CollectionDao {

    @Query("SELECT * FROM account_collections ORDER BY displayOrder ASC, updatedAt DESC")
    fun observeCollections(): Flow<List<CollectionEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCollection(collection: CollectionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(collections: List<CollectionEntity>)

    @Query("DELETE FROM account_collections WHERE id = :id")
    suspend fun deleteCollection(id: String)
}
