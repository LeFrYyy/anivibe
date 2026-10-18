package com.anivibe.app.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

object DatabaseMigrations {

    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // 1. Recreate watch_progress with sourceKey if missing
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS watch_progress_new (
                    animeId INTEGER NOT NULL,
                    episode INTEGER NOT NULL,
                    sourceKey TEXT NOT NULL DEFAULT '',
                    positionSeconds REAL NOT NULL,
                    durationSeconds REAL NOT NULL,
                    updatedAt INTEGER NOT NULL,
                    PRIMARY KEY(animeId, episode, sourceKey)
                )
            """.trimIndent())
            db.execSQL("""
                INSERT OR IGNORE INTO watch_progress_new (animeId, episode, sourceKey, positionSeconds, durationSeconds, updatedAt)
                SELECT animeId, episode, '', positionSeconds, durationSeconds, updatedAt FROM watch_progress
            """.trimIndent())
            db.execSQL("DROP TABLE IF EXISTS watch_progress")
            db.execSQL("ALTER TABLE watch_progress_new RENAME TO watch_progress")

            // 2. Add deletedAt to watch_history if not present
            try {
                db.execSQL("ALTER TABLE watch_history ADD COLUMN deletedAt INTEGER DEFAULT NULL")
            } catch (e: Exception) {
                // column might already exist
            }

            // 3. Create account_collections if not present
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS account_collections (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    emoji TEXT NOT NULL DEFAULT '📁',
                    animeIdsJson TEXT NOT NULL DEFAULT '[]',
                    displayOrder INTEGER NOT NULL DEFAULT 0,
                    updatedAt INTEGER NOT NULL
                )
            """.trimIndent())
        }
    }
}
