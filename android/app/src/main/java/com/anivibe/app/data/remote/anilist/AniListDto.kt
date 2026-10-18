package com.anivibe.app.data.remote.anilist

import com.anivibe.app.data.model.*
import kotlinx.serialization.Serializable

@Serializable
data class GraphQLRequest(
    val query: String,
    val variables: Map<String, kotlinx.serialization.json.JsonElement>? = null
)

@Serializable
data class AniListResponse<T>(
    val data: T? = null,
    val errors: List<GraphQLError>? = null
)

@Serializable
data class GraphQLError(
    val message: String,
    val status: Int? = null
)

@Serializable
data class AniListHomeData(
    val popular: AniListPageDto? = null,
    val seasonal: AniListPageDto? = null,
    val trending: AniListPageDto? = null,
    val recent: AniListPageDto? = null
)

@Serializable
data class AniListSearchData(
    val Page: AniListPageDto? = null
)

@Serializable
data class AniListDetailsData(
    val Media: AniListMediaDto? = null
)

@Serializable
data class AniListRecentEpisodesData(
    val Page: AniListSchedulePageDto? = null
)

@Serializable
data class AniListPageDto(
    val pageInfo: AniListPageInfoDto? = null,
    val media: List<AniListMediaDto> = emptyList()
)

@Serializable
data class AniListPageInfoDto(
    val currentPage: Int = 1,
    val hasNextPage: Boolean = false
)

@Serializable
data class AniListSchedulePageDto(
    val airingSchedules: List<AniListAiringScheduleDto> = emptyList()
)

@Serializable
data class AniListAiringScheduleDto(
    val episode: Int,
    val airingAt: Long,
    val media: AniListMediaDto? = null
)

@Serializable
data class AniListMediaDto(
    val id: Int,
    val idMal: Int? = null,
    val title: AniListTitleDto? = null,
    val synonyms: List<String> = emptyList(),
    val coverImage: AniListCoverDto? = null,
    val bannerImage: String? = null,
    val seasonYear: Int? = null,
    val season: String? = null,
    val genres: List<String> = emptyList(),
    val status: String? = null,
    val format: String? = null,
    val averageScore: Int? = null,
    val episodes: Int? = null,
    val duration: Int? = null,
    val nextAiringEpisode: AniListNextEpisodeDto? = null,
    val isAdult: Boolean = false,
    val description: String? = null,
    val relations: AniListRelationsDto? = null,
    val streamingEpisodes: List<AniListStreamingEpisodeDto> = emptyList(),
    val externalLinks: List<AniListExternalLinkDto> = emptyList(),
    val studios: AniListStudiosDto? = null,
    val recommendations: AniListRecommendationsDto? = null
) {
    fun toModel(): Anime {
        return Anime(
            id = id,
            malId = idMal,
            title = AnimeTitle(
                romaji = title?.romaji,
                english = title?.english,
                native = title?.native
            ),
            coverImage = AnimeCoverImage(
                large = coverImage?.large,
                extraLarge = coverImage?.extraLarge,
                color = coverImage?.color
            ),
            bannerImage = bannerImage,
            format = format?.let {
                try { AnimeFormat.valueOf(it) } catch (e: Exception) { null }
            },
            status = status?.let {
                try { AnimeStatus.valueOf(it) } catch (e: Exception) { null }
            },
            seasonYear = seasonYear,
            season = season?.let {
                try { AnimeSeason.valueOf(it) } catch (e: Exception) { null }
            },
            episodes = episodes,
            duration = duration,
            averageScore = averageScore,
            isAdult = isAdult,
            nextAiringEpisode = nextAiringEpisode?.episode,
            synopsis = description,
            genres = genres,
            synonyms = synonyms,
            studios = studios?.nodes?.mapNotNull { it.name } ?: emptyList(),
            relations = relations?.edges?.mapNotNull { edge ->
                edge.node?.let { node ->
                    AnimeRelation(
                        relationType = edge.relationType ?: "RELATION",
                        anime = node.toModel()
                    )
                }
            } ?: emptyList(),
            recommendations = recommendations?.nodes?.mapNotNull {
                it.mediaRecommendation?.toModel()
            } ?: emptyList(),
            streamingEpisodes = streamingEpisodes.map {
                StreamingEpisode(it.title, it.thumbnail, it.url, it.site)
            },
            externalLinks = externalLinks.map {
                ExternalLink(it.site ?: "", it.url ?: "", it.type)
            }
        )
    }
}

@Serializable
data class AniListTitleDto(
    val romaji: String? = null,
    val english: String? = null,
    val native: String? = null
)

@Serializable
data class AniListCoverDto(
    val large: String? = null,
    val extraLarge: String? = null,
    val color: String? = null
)

@Serializable
data class AniListNextEpisodeDto(
    val episode: Int
)

@Serializable
data class AniListRelationsDto(
    val edges: List<AniListRelationEdgeDto> = emptyList()
)

@Serializable
data class AniListRelationEdgeDto(
    val relationType: String? = null,
    val node: AniListMediaDto? = null
)

@Serializable
data class AniListStudiosDto(
    val nodes: List<AniListStudioNodeDto> = emptyList()
)

@Serializable
data class AniListStudioNodeDto(
    val name: String? = null
)

@Serializable
data class AniListRecommendationsDto(
    val nodes: List<AniListRecommendationNodeDto> = emptyList()
)

@Serializable
data class AniListRecommendationNodeDto(
    val mediaRecommendation: AniListMediaDto? = null
)

@Serializable
data class AniListStreamingEpisodeDto(
    val title: String? = null,
    val thumbnail: String? = null,
    val url: String? = null,
    val site: String? = null
)

@Serializable
data class AniListExternalLinkDto(
    val site: String? = null,
    val url: String? = null,
    val type: String? = null
)
