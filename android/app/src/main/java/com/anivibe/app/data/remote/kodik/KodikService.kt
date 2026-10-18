package com.anivibe.app.data.remote.kodik

import com.anivibe.app.core.util.TitleMatcher
import com.anivibe.app.data.model.KodikMaterialDto
import com.anivibe.app.data.model.KodikSearchResponse
import com.anivibe.app.data.model.KodikStream
import com.anivibe.app.data.model.ProviderEpisode
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter

class KodikService(
    private val client: HttpClient,
    private val tokenProvider: () -> String?
) {
    private val baseUrl = "https://kodik-api.com"
    private val streamResolver = KodikStreamResolver(client)

    suspend fun searchMaterials(
        shikimoriId: Int? = null,
        titles: List<String> = emptyList(),
        year: Int? = null
    ): List<KodikMaterialDto> {
        val token = tokenProvider()?.trim()
        if (token.isNullOrEmpty()) return emptyList()

        if (shikimoriId != null) {
            val byId = requestSearch(mapOf("shikimori_id" to shikimoriId.toString(), "token" to token))
            val exact = byId.filter { it.shikimoriId == null || it.shikimoriId == shikimoriId.toString() }
            if (exact.isNotEmpty()) return exact
        }

        for (title in titles) {
            if (title.isBlank()) continue
            val list = requestSearch(mapOf("title" to title.trim(), "token" to token))
            if (list.isNotEmpty()) {
                val matched = list.filter { mat ->
                    val matTitle = mat.title
                    val matOrig = mat.titleOrig ?: ""
                    titles.any { t -> TitleMatcher.matches(t, matTitle) || TitleMatcher.matches(t, matOrig) }
                }
                if (matched.isNotEmpty()) return matched
            }
        }
        return emptyList()
    }

    private suspend fun requestSearch(params: Map<String, String>): List<KodikMaterialDto> {
        return try {
            val response: KodikSearchResponse = client.get("$baseUrl/search") {
                parameter("types", "anime,anime-serial")
                parameter("limit", "100")
                parameter("with_episodes", "true")
                parameter("with_episodes_data", "true")
                for ((k, v) in params) {
                    parameter(k, v)
                }
            }.body()
            response.results
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun resolveDirectStreams(playerUrl: String): List<KodikStream> {
        return streamResolver.resolveStreams(playerUrl)
    }

    fun buildEpisodeList(material: KodikMaterialDto): List<ProviderEpisode> {
        val episodes = mutableListOf<ProviderEpisode>()
        val seasons = material.seasons ?: return emptyList()

        for ((seasonNum, seasonData) in seasons) {
            val epMap = seasonData.episodes ?: continue
            for ((epNumStr, link) in epMap) {
                val epNum = epNumStr.toIntOrNull() ?: continue
                val fullLink = if (link.startsWith("//")) "https:$link" else link
                val translationName = material.translation?.title ?: "Оригинал"
                val sourceKey = "kodik:${material.id}:$seasonNum:$epNum"

                episodes.add(
                    ProviderEpisode(
                        episodeNumber = epNum,
                        title = "Серия $epNum ($translationName)",
                        webPlayerUrl = fullLink,
                        providerId = "kodik",
                        sourceKey = sourceKey,
                        translationTitle = translationName
                    )
                )
            }
        }
        return episodes.sortedBy { it.episodeNumber }
    }
}
