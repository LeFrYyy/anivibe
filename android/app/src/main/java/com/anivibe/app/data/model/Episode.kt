package com.anivibe.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class KodikSearchResponse(
    val time: String? = null,
    val total: Int = 0,
    val results: List<KodikMaterialDto> = emptyList()
)

@Serializable
data class KodikMaterialDto(
    val id: String,
    val title: String,
    @SerialName("title_orig") val titleOrig: String? = null,
    @SerialName("other_title") val otherTitle: String? = null,
    val link: String,
    val year: Int? = null,
    val type: String? = null,
    @SerialName("kinopoisk_id") val kinopoiskId: String? = null,
    @SerialName("shikimori_id") val shikimoriId: String? = null,
    val translation: KodikTranslationDto? = null,
    @SerialName("episodes_count") val episodesCount: Int? = null,
    val seasons: Map<String, KodikSeasonDto>? = null
)

@Serializable
data class KodikTranslationDto(
    val id: Int,
    val title: String,
    val type: String? = null
)

@Serializable
data class KodikSeasonDto(
    val link: String? = null,
    val title: String? = null,
    val episodes: Map<String, String>? = null // episodeNumber -> link or info
)

@Serializable
data class KodikStream(
    val quality: Int,
    val url: String
) {
    val label: String get() = "${quality}p"
}

@Serializable
data class ProviderEpisode(
    val episodeNumber: Int,
    val title: String? = null,
    val hlsUrl: String? = null,
    val mp4Url: String? = null,
    val webPlayerUrl: String? = null,
    val providerId: String,
    val sourceKey: String,
    val translationTitle: String? = null,
    val availableQualities: List<KodikStream> = emptyList()
)
