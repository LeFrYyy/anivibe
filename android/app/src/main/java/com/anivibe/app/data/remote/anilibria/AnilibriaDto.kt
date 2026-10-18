package com.anivibe.app.data.remote.anilibria

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AnilibriaTitleNames(
    val main: String? = null,
    val english: String? = null,
    val alternative: String? = null
)

@Serializable
data class AnilibriaExternalRef(
    val id: Int? = null,
    val url: String? = null
)

@Serializable
data class AnilibriaReleaseSummary(
    val id: Int,
    val name: AnilibriaTitleNames? = null,
    val year: Int? = null,
    val mal: AnilibriaExternalRef? = null,
    val shikimori: AnilibriaExternalRef? = null
)

@Serializable
data class AnilibriaRelease(
    val id: Int,
    val name: AnilibriaTitleNames? = null,
    @SerialName("is_blocked_by_geo") val isBlockedByGeo: Boolean? = null,
    @SerialName("is_blocked_by_copyrights") val isBlockedByCopyrights: Boolean? = null,
    val episodes: List<AnilibriaEpisodeDto>? = null
)

@Serializable
data class AnilibriaEpisodeDto(
    val id: String? = null,
    val name: String? = null,
    val ordinal: Double? = null,
    val hls: AnilibriaHlsDto? = null
)

@Serializable
data class AnilibriaHlsDto(
    val fhd: String? = null,
    val hd: String? = null,
    val sd: String? = null
) {
    val bestUrl: String?
        get() = fhd ?: hd ?: sd
}
