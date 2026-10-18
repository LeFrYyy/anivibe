package com.anivibe.app.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.anivibe.app.data.local.dao.CollectionDao
import com.anivibe.app.data.local.dao.LibraryDao
import com.anivibe.app.data.local.dao.WatchHistoryDao
import com.anivibe.app.data.local.dao.WatchProgressDao
import com.anivibe.app.data.local.entity.CollectionEntity
import com.anivibe.app.data.local.entity.LibraryEntryEntity
import com.anivibe.app.data.local.entity.WatchHistoryEntity
import com.anivibe.app.data.local.entity.WatchProgressEntity

@Database(
    entities = [
        LibraryEntryEntity::class,
        WatchProgressEntity::class,
        WatchHistoryEntity::class,
        CollectionEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class AnivibeDatabase : RoomDatabase() {

    abstract fun libraryDao(): LibraryDao
    abstract fun watchProgressDao(): WatchProgressDao
    abstract fun watchHistoryDao(): WatchHistoryDao
    abstract fun collectionDao(): CollectionDao

    companion object {
        @Volatile
        private var INSTANCE: AnivibeDatabase? = null

        fun getDatabase(context: Context): AnivibeDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AnivibeDatabase::class.java,
                    "anivibe_local.db"
                )
                    .addMigrations(DatabaseMigrations.MIGRATION_1_2)
                    .fallbackToDestructiveMigrationOnDowngrade()
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
