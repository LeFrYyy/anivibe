package com.anivibe.app.data.repository

import com.anivibe.app.data.model.Anime
import com.anivibe.app.data.model.KodikMaterialDto
import com.anivibe.app.data.model.ProviderEpisode
import com.anivibe.app.data.remote.anilibria.AnilibriaRelease
import com.anivibe.app.data.remote.anilibria.AnilibriaService
import com.anivibe.app.data.remote.kodik.KodikService
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

class VideoSourceRepository(
    private val kodikService: KodikService,
    private val anilibriaService: AnilibriaService
) {
    data class AnimeSources(
        val kodikMaterials: List<KodikMaterialDto>,
        val anilibriaRelease: AnilibriaRelease?
    )

    suspend fun findSources(anime: Anime): AnimeSources = coroutineScope {
        val titles = listOfNotNull(
            anime.title.russian,
            anime.title.english,
            anime.title.romaji,
            anime.title.native
        ) + anime.synonyms

        val kodikDeferred = async {
            kodikService.searchMaterials(
                shikimoriId = anime.malId,
                titles = titles,
                year = anime.seasonYear
            )
        }

        val anilibriaDeferred = async {
            anilibriaService.findRelease(
                malId = anime.malId,
                titles = titles,
                year = anime.seasonYear
            )
        }

        AnimeSources(
            kodikMaterials = kodikDeferred.await(),
            anilibriaRelease = anilibriaDeferred.await()
        )
    }

    suspend fun getEpisodes(
        material: KodikMaterialDto?,
        release: AnilibriaRelease?
    ): List<ProviderEpisode> {
        if (material != null) {
            val episodes = kodikService.buildEpisodeList(material)
            if (episodes.isNotEmpty()) return episodes
        }
        if (release != null) {
            return anilibriaService.buildEpisodes(release)
        }
        return emptyList()
    }

    suspend fun resolveStream(episode: ProviderEpisode): ProviderEpisode {
        if (episode.providerId == "kodik" && !episode.webPlayerUrl.isNullOrEmpty()) {
            val directStreams = kodikService.resolveDirectStreams(episode.webPlayerUrl)
            if (directStreams.isNotEmpty()) {
                val best = directStreams.first()
                return episode.copy(
                    hlsUrl = best.url,
                    availableQualities = directStreams
                )
            }
        }
        return episode
    }
}
