package com.anivibe.app.data.remote.shikimori

import com.anivibe.app.core.util.HtmlTextCleaner
import com.anivibe.app.data.model.Anime
import kotlinx.serialization.Serializable

@Serializable
data class ShikimoriAnimeDto(
    val id: Int,
    val name: String? = null,
    val russian: String? = null,
    val synonyms: List<String> = emptyList(),
    val description: String? = null
) {
    fun applyTo(original: Anime): Anime {
        if (original.malId != id) return original
        val cleanSynopsis = HtmlTextCleaner.clean(description)
        return original.copy(
            title = original.title.copy(
                russian = russian?.ifBlank { null } ?: original.title.russian
            ),
            synopsis = if (cleanSynopsis.isNotBlank()) cleanSynopsis else original.synopsis,
            synopsisSource = if (cleanSynopsis.isNotBlank()) "Shikimori" else original.synopsisSource,
            synonyms = (original.synonyms + synonyms + listOfNotNull(name, russian)).distinct().sorted()
        )
    }
}
