package com.anivibe.app.data.remote.anilist

import com.anivibe.app.core.network.RateLimiter
import com.anivibe.app.data.model.*
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.json.*

class AniListService(
    private val client: HttpClient,
    private val rateLimiter: RateLimiter = RateLimiter(maxTokens = 30, perPeriodMillis = 60_000)
) {
    private val endpoint = "https://graphql.anilist.co"

    data class HomeFeed(
        val trending: List<Anime>,
        val seasonal: List<Anime>,
        val popular: List<Anime>,
        val recent: List<Anime>
    )

    data class SearchResult(
        val items: List<Anime>,
        val currentPage: Int,
        val hasNextPage: Boolean
    )

    suspend fun getHomeFeed(perPage: Int = 16): HomeFeed {
        rateLimiter.acquire()
        val calendar = java.util.Calendar.getInstance()
        val year = calendar.get(java.util.Calendar.YEAR)
        val month = calendar.get(java.util.Calendar.MONTH) // 0-indexed
        val season = when (month) {
            11, 0, 1 -> "WINTER"
            2, 3, 4 -> "SPRING"
            5, 6, 7 -> "SUMMER"
            else -> "FALL"
        }

        val vars = buildJsonObject {
            put("season", season)
            put("seasonYear", year)
            put("perPage", perPage)
        }

        val request = GraphQLRequest(AniListQueries.HOME, vars)
        val response: AniListResponse<AniListHomeData> = client.post(endpoint) {
            contentType(ContentType.Application.Json)
            setBody(request)
        }.body()

        val data = response.data ?: throw Exception("Не удалось загрузить данные главной с AniList")
        return HomeFeed(
            trending = data.trending?.media?.map { it.toModel() } ?: emptyList(),
            seasonal = data.seasonal?.media?.map { it.toModel() } ?: emptyList(),
            popular = data.popular?.media?.map { it.toModel() } ?: emptyList(),
            recent = data.recent?.media?.map { it.toModel() } ?: emptyList()
        )
    }

    suspend fun search(
        query: String? = null,
        page: Int = 1,
        perPage: Int = 24,
        genres: List<String>? = null,
        year: Int? = null,
        season: AnimeSeason? = null,
        status: AnimeStatus? = null,
        format: AnimeFormat? = null,
        sort: AnimeSort = AnimeSort.POPULARITY_DESC
    ): SearchResult {
        rateLimiter.acquire()
        val vars = buildJsonObject {
            put("page", page)
            put("perPage", perPage)
            if (!query.isNullOrBlank()) put("search", query.trim())
            if (!genres.isNullOrEmpty()) {
                put("genres", buildJsonArray { genres.forEach { add(it) } })
            }
            if (year != null) put("year", year)
            if (season != null) put("season", season.name)
            if (status != null) put("status", status.name)
            if (format != null) {
                put("formats", buildJsonArray { add(format.name) })
            }
            put("sort", buildJsonArray { add(sort.name) })
        }

        val request = GraphQLRequest(AniListQueries.SEARCH, vars)
        val response: AniListResponse<AniListSearchData> = client.post(endpoint) {
            contentType(ContentType.Application.Json)
            setBody(request)
        }.body()

        val pageData = response.data?.Page ?: return SearchResult(emptyList(), page, false)
        return SearchResult(
            items = pageData.media.map { it.toModel() },
            currentPage = pageData.pageInfo?.currentPage ?: page,
            hasNextPage = pageData.pageInfo?.hasNextPage ?: false
        )
    }

    suspend fun getDetails(id: Int): Anime {
        rateLimiter.acquire()
        val vars = buildJsonObject {
            put("id", id)
        }
        val request = GraphQLRequest(AniListQueries.DETAILS, vars)
        val response: AniListResponse<AniListDetailsData> = client.post(endpoint) {
            contentType(ContentType.Application.Json)
            setBody(request)
        }.body()

        return response.data?.Media?.toModel() ?: throw Exception("Аниме #$id не найдено на AniList")
    }

    suspend fun getRecentEpisodes(perPage: Int = 20): List<AiredEpisode> {
        rateLimiter.acquire()
        val nowSeconds = System.currentTimeMillis() / 1000
        val from = nowSeconds - 86400 * 3
        val to = nowSeconds + 86400 * 2

        val vars = buildJsonObject {
            put("from", from)
            put("to", to)
            put("perPage", perPage)
        }
        val request = GraphQLRequest(AniListQueries.RECENT_EPISODES, vars)
        val response: AniListResponse<AniListRecentEpisodesData> = client.post(endpoint) {
            contentType(ContentType.Application.Json)
            setBody(request)
        }.body()

        return response.data?.Page?.airingSchedules?.mapNotNull { sched ->
            sched.media?.let { media ->
                AiredEpisode(
                    episode = sched.episode,
                    airingAt = sched.airingAt,
                    anime = media.toModel()
                )
            }
        } ?: emptyList()
    }
}
