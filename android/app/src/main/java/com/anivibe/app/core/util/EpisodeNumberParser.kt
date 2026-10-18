package com.anivibe.app.core.util

object EpisodeNumberParser {
    private val EPISODE_REGEX = Regex("(?:серия|эпизод|ep|episode|выпуск)\\s*(\\d+)", RegexOption.IGNORE_CASE)
    private val STANDALONE_NUMBER_REGEX = Regex("^(\\d+)$")

    fun parse(text: String): Int? {
        val trimmed = text.trim()
        STANDALONE_NUMBER_REGEX.find(trimmed)?.groupValues?.get(1)?.toIntOrNull()?.let {
            return it
        }
        EPISODE_REGEX.find(trimmed)?.groupValues?.get(1)?.toIntOrNull()?.let {
            return it
        }
        val numbers = Regex("\\d+").findAll(trimmed).mapNotNull { it.value.toIntOrNull() }.toList()
        return numbers.lastOrNull()
    }
}
