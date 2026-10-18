package com.anivibe.app.data.model

import kotlinx.serialization.Serializable

@Serializable
data class Anime(
    val id: Int,
    val malId: Int? = null,
    val title: AnimeTitle,
    val coverImage: AnimeCoverImage? = null,
    val bannerImage: String? = null,
    val format: AnimeFormat? = null,
    val status: AnimeStatus? = null,
    val seasonYear: Int? = null,
    val season: AnimeSeason? = null,
    val episodes: Int? = null,
    val duration: Int? = null,
    val averageScore: Int? = null,
    val isAdult: Boolean = false,
    val nextAiringEpisode: Int? = null,
    val synopsis: String? = null,
    val synopsisOriginal: String? = null,
    val synopsisSource: String? = null,
    val genres: List<String> = emptyList(),
    val synonyms: List<String> = emptyList(),
    val studios: List<String> = emptyList(),
    val relations: List<AnimeRelation> = emptyList(),
    val recommendations: List<Anime> = emptyList(),
    val streamingEpisodes: List<StreamingEpisode> = emptyList(),
    val externalLinks: List<ExternalLink> = emptyList()
) {
    val displayTitle: String
        get() = title.russian ?: title.english ?: title.romaji ?: title.native ?: "Аниме #$id"

    val yearText: String
        get() = seasonYear?.toString() ?: ""

    val scoreText: String
        get() = averageScore?.let { String.format("%.1f", it / 10.0) } ?: "-"
}

@Serializable
data class AnimeTitle(
    val romaji: String? = null,
    val english: String? = null,
    val native: String? = null,
    var russian: String? = null
) {
    val preferred: String
        get() = russian ?: english ?: romaji ?: native ?: ""
}

@Serializable
data class AnimeCoverImage(
    val large: String? = null,
    val extraLarge: String? = null,
    val color: String? = null
) {
    val bestUrl: String?
        get() = extraLarge ?: large
}

@Serializable
enum class AnimeFormat(val displayName: String) {
    TV("ТВ"),
    TV_SHORT("ТВ (короткое)"),
    MOVIE("Фильм"),
    SPECIAL("Спецвыпуск"),
    OVA("OVA"),
    ONA("ONA"),
    MUSIC("Клип")
}

@Serializable
enum class AnimeStatus(val displayName: String) {
    FINISHED("Вышло"),
    RELEASING("Онгоинг"),
    NOT_YET_RELEASED("Анонс"),
    CANCELLED("Отменено"),
    HIATUS("Приостановлено")
}

@Serializable
enum class AnimeSeason(val displayName: String) {
    WINTER("Зима"),
    SPRING("Весна"),
    SUMMER("Лето"),
    FALL("Осень")
}

@Serializable
enum class AnimeSort(val displayName: String) {
    TRENDING_DESC("В тренде"),
    POPULARITY_DESC("По популярности"),
    SCORE_DESC("По рейтингу"),
    START_DATE_DESC("По дате выхода"),
    TITLE_ROMAJI("По алфавиту")
}

@Serializable
data class AnimeRelation(
    val relationType: String,
    val anime: Anime
)

@Serializable
data class StreamingEpisode(
    val title: String? = null,
    val thumbnail: String? = null,
    val url: String? = null,
    val site: String? = null
)

@Serializable
data class ExternalLink(
    val site: String,
    val url: String,
    val type: String? = null
)

@Serializable
data class AiredEpisode(
    val episode: Int,
    val airingAt: Long,
    val anime: Anime
)
