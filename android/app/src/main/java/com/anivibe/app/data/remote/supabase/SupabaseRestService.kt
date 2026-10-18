package com.anivibe.app.data.remote.supabase

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class LibraryEntryRow(
    @SerialName("user_id") val userId: String,
    @SerialName("anime_id") val animeId: Int,
    val title: String,
    @SerialName("cover_url") val coverUrl: String? = null,
    @SerialName("episode_count") val episodeCount: Int? = null,
    val status: String? = null,
    @SerialName("is_favorite") val isFavorite: Boolean = false,
    @SerialName("last_episode") val lastEpisode: Int? = null,
    @SerialName("is_deleted") val isDeleted: Boolean = false,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
data class WatchProgressRow(
    @SerialName("user_id") val userId: String,
    @SerialName("anime_id") val animeId: Int,
    val episode: Int,
    @SerialName("source_key") val sourceKey: String = "",
    @SerialName("position_seconds") val positionSeconds: Double,
    @SerialName("duration_seconds") val durationSeconds: Double,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
data class WatchHistoryRow(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("anime_id") val animeId: Int,
    val title: String,
    @SerialName("cover_url") val coverUrl: String? = null,
    val episode: Int,
    @SerialName("watched_at") val watchedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null
)

@Serializable
data class CollectionRow(
    val id: String,
    @SerialName("user_id") val userId: String,
    val name: String,
    val emoji: String,
    @SerialName("anime_ids") val animeIds: List<Int> = emptyList(),
    @SerialName("display_order") val displayOrder: Int = 0,
    @SerialName("updated_at") val updatedAt: String
)

class SupabaseRestService(
    private val client: HttpClient,
    private val supabaseUrl: String,
    private val anonKey: String
) {
    suspend inline fun <reified T> fetchTable(
        table: String,
        token: String,
        timeColumn: String? = null,
        sinceIso: String? = null
    ): List<T> {
        val url = "$supabaseUrl/rest/v1/$table"
        return try {
            client.get(url) {
                header("apikey", anonKey)
                header("Authorization", "Bearer $token")
                header("Accept", "application/json")
                if (timeColumn != null && sinceIso != null) {
                    parameter(timeColumn, "gt.$sinceIso")
                }
            }.body()
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend inline fun <reified T> upsertTable(
        table: String,
        conflict: String,
        rows: List<T>,
        token: String
    ) {
        if (rows.isEmpty()) return
        val url = "$supabaseUrl/rest/v1/$table"
        client.post(url) {
            contentType(ContentType.Application.Json)
            header("apikey", anonKey)
            header("Authorization", "Bearer $token")
            header("Prefer", "resolution=merge-duplicates,return=minimal")
            parameter("on_conflict", conflict)
            setBody(rows)
        }
    }
}
