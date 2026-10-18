package com.anivibe.app.core.util

object HtmlTextCleaner {
    private val HTML_TAG_REGEX = Regex("<[^>]*>")
    private val SHIKIMORI_BBCODE_REGEX = Regex("\\[/?(?:anime|manga|character|person|url|b|i|u|s|spoiler|quote|size|color)(?:=[^\\]]*)?]")

    fun clean(input: String?): String {
        if (input.isNullOrBlank()) return ""
        var text = input
        text = HTML_TAG_REGEX.replace(text, "")
        text = SHIKIMORI_BBCODE_REGEX.replace(text, "")
        text = text
            .replace("&quot;", "\"")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&#39;", "'")
            .replace("&nbsp;", " ")
        return text.trim()
    }
}
