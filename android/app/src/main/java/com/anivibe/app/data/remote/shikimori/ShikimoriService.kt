package com.anivibe.app.data.remote.shikimori

import com.anivibe.app.core.network.RateLimiter
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter

class ShikimoriService(
    private val client: HttpClient,
    private val rateLimiter: RateLimiter = RateLimiter(maxTokens = 4, perPeriodMillis = 1000)
) {
    private val baseUrl = "https://shikimori.io/api"

    suspend fun getTitles(malIds: List<Int>): List<ShikimoriAnimeDto> {
        val validIds = malIds.filter { it > 0 }.distinct().take(50)
        if (validIds.isEmpty()) return emptyList()

        return try {
            rateLimiter.acquire()
            val idsParam = validIds.joinToString(",")
            client.get("$baseUrl/animes") {
                parameter("ids", idsParam)
                parameter("limit", "50")
                parameter("censored", "true")
            }.body()
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun search(query: String, page: Int = 1, limit: Int = 20): List<ShikimoriAnimeDto> {
        if (query.isBlank()) return emptyList()

        return try {
            rateLimiter.acquire()
            client.get("$baseUrl/animes") {
                parameter("search", query.take(100))
                parameter("page", page)
                parameter("limit", limit.coerceAtMost(50))
                parameter("censored", "true")
            }.body()
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun getDetails(malId: Int): ShikimoriAnimeDto? {
        if (malId <= 0) return null
        return try {
            rateLimiter.acquire()
            client.get("$baseUrl/animes/$malId").body()
        } catch (e: Exception) {
            null
        }
    }
}
