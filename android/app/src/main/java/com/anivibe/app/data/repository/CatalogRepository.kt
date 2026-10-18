package com.anivibe.app.data.repository

import com.anivibe.app.core.util.TitleMatcher
import com.anivibe.app.data.model.*
import com.anivibe.app.data.remote.anilist.AniListService
import com.anivibe.app.data.remote.shikimori.ShikimoriService
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

class CatalogRepository(
    private val aniListService: AniListService,
    private val shikimoriService: ShikimoriService
) {
    suspend fun getHomeFeed(): AniListService.HomeFeed = coroutineScope {
        val baseFeed = aniListService.getHomeFeed(perPage = 16)

        // Collect all MAL IDs across home sections to enrich with Russian titles
        val allAnime = baseFeed.trending + baseFeed.seasonal + baseFeed.popular + baseFeed.recent
        val malIds = allAnime.mapNotNull { it.malId }
        val shikimoriMap = shikimoriService.getTitles(malIds).associateBy { it.id }

        AniListService.HomeFeed(
            trending = baseFeed.trending.map { anime -> anime.malId?.let { shikimoriMap[it]?.applyTo(anime) } ?: anime },
            seasonal = baseFeed.seasonal.map { anime -> anime.malId?.let { shikimoriMap[it]?.applyTo(anime) } ?: anime },
            popular = baseFeed.popular.map { anime -> anime.malId?.let { shikimoriMap[it]?.applyTo(anime) } ?: anime },
            recent = baseFeed.recent.map { anime -> anime.malId?.let { shikimoriMap[it]?.applyTo(anime) } ?: anime }
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
    ): AniListService.SearchResult = coroutineScope {
        val trimmed = query?.trim().orEmpty()
        val hasCyrillic = trimmed.any { it in 'а'..'я' || it in 'А'..'Я' || it == 'ё' || it == 'Ё' }

        // If Cyrillic search, first search Shikimori to get matching titles / MAL IDs
        val shikimoriMatches = if (hasCyrillic && trimmed.isNotEmpty()) {
            val direct = shikimoriService.search(trimmed, page = page, limit = perPage)
            if (direct.isEmpty()) {
                shikimoriService.search(TitleMatcher.transliterate(trimmed), page = page, limit = perPage)
            } else direct
        } else emptyList()

        val effectiveQuery = if (hasCyrillic && shikimoriMatches.isNotEmpty()) {
            shikimoriMatches.firstNotNullOfOrNull { it.name } ?: TitleMatcher.transliterate(trimmed)
        } else trimmed

        val result = aniListService.search(
            query = effectiveQuery.ifEmpty { null },
            page = page,
            perPage = perPage,
            genres = genres,
            year = year,
            season = season,
            status = status,
            format = format,
            sort = sort
        )

        val malIds = result.items.mapNotNull { it.malId }
        val shikimoriMap = shikimoriService.getTitles(malIds).associateBy { it.id }

        val localized = result.items.map { anime ->
            anime.malId?.let { shikimoriMap[it]?.applyTo(anime) } ?: anime
        }

        result.copy(items = localized)
    }

    suspend fun getDetails(id: Int): Anime = coroutineScope {
        val base = aniListService.getDetails(id)
        if (base.malId != null) {
            val shiki = shikimoriService.getDetails(base.malId)
            if (shiki != null) {
                return@coroutineScope shiki.applyTo(base)
            }
        }
        base
    }

    suspend fun getRecentEpisodes(): List<AiredEpisode> {
        val list = aniListService.getRecentEpisodes()
        val malIds = list.mapNotNull { it.anime.malId }
        val shikiMap = shikimoriService.getTitles(malIds).associateBy { it.id }

        return list.map { aired ->
            val enriched = aired.anime.malId?.let { shikiMap[it]?.applyTo(aired.anime) } ?: aired.anime
            aired.copy(anime = enriched)
        }
    }
}
