package com.anivibe.app.data.remote.anilibria

import com.anivibe.app.core.util.TitleMatcher
import com.anivibe.app.data.model.ProviderEpisode
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class AnilibriaService(
    private val client: HttpClient
) {
    private val mirrors = listOf(
        "https://anilibria.top/api/v1",
        "https://api.anilibria.app/api/v1",
        "https://aniliberty.top/api/v1"
    )
    private var activeMirrorIndex = 0
    private val mirrorMutex = Mutex()

    private suspend fun <T> executeWithMirror(block: suspend (baseUrl: String) -> T): T? {
        val total = mirrors.size
        for (i in 0 until total) {
            val url = mirrorMutex.withLock { mirrors[(activeMirrorIndex + i) % total] }
            try {
                val result = block(url)
                mirrorMutex.withLock { activeMirrorIndex = (activeMirrorIndex + i) % total }
                return result
            } catch (e: Exception) {
                // Try next mirror
            }
        }
        return null
    }

    suspend fun findRelease(
        malId: Int? = null,
        titles: List<String> = emptyList(),
        year: Int? = null
    ): AnilibriaRelease? {
        return executeWithMirror { baseUrl ->
            if (malId != null) {
                val list: List<AnilibriaReleaseSummary> = client.get("$baseUrl/anime/catalog/releases") {
                    parameter("page", 1)
                    parameter("limit", 50)
                }.body()
                val exact = list.firstOrNull { it.mal?.id == malId || it.shikimori?.id == malId }
                if (exact != null) {
                    val full: AnilibriaRelease = client.get("$baseUrl/anime/releases/${exact.id}").body()
                    return@executeWithMirror full
                }
            }

            for (title in titles) {
                if (title.isBlank()) continue
                val searchResults: List<AnilibriaReleaseSummary> = client.get("$baseUrl/anime/catalog/releases") {
                    parameter("search", title.trim())
                    parameter("limit", 20)
                }.body()

                val matched = searchResults.firstOrNull { summary ->
                    val main = summary.name?.main ?: ""
                    val eng = summary.name?.english ?: ""
                    val alt = summary.name?.alternative ?: ""
                    titles.any { t ->
                        TitleMatcher.matches(t, main) ||
                                TitleMatcher.matches(t, eng) ||
                                TitleMatcher.matches(t, alt)
                    }
                }
                if (matched != null) {
                    val full: AnilibriaRelease = client.get("$baseUrl/anime/releases/${matched.id}").body()
                    return@executeWithMirror full
                }
            }
            null
        }
    }

    fun buildEpisodes(release: AnilibriaRelease): List<ProviderEpisode> {
        val episodes = mutableListOf<ProviderEpisode>()
        val rawEpisodes = release.episodes ?: return emptyList()

        for (ep in rawEpisodes) {
            val epNum = ep.ordinal?.toInt() ?: continue
            val hlsUrl = ep.hls?.bestUrl ?: continue
            val sourceKey = "anilibria:${release.id}:$epNum"

            episodes.add(
                ProviderEpisode(
                    episodeNumber = epNum,
                    title = ep.name ?: "Серия $epNum (Анилибрия)",
                    hlsUrl = hlsUrl,
                    providerId = "anilibria",
                    sourceKey = sourceKey,
                    translationTitle = "Anilibria"
                )
            )
        }
        return episodes.sortedBy { it.episodeNumber }
    }
}
