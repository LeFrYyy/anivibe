package com.anivibe.app.core.util

object TitleMatcher {

    fun normalize(title: String): String {
        return title.lowercase()
            .replace(Regex("[^a-zа-яё0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    fun matches(query: String, target: String): Boolean {
        val nq = normalize(query)
        val nt = normalize(target)
        if (nq.isEmpty() || nt.isEmpty()) return false
        if (nt == nq || nt.contains(nq) || nq.contains(nt)) return true

        // Levenshtein / Word match
        val wordsQ = nq.split(" ").filter { it.length > 2 }
        val wordsT = nt.split(" ").filter { it.length > 2 }
        if (wordsQ.isNotEmpty() && wordsT.isNotEmpty()) {
            val common = wordsQ.count { wq -> wordsT.any { wt -> wt == wq || wt.startsWith(wq) || wq.startsWith(wt) } }
            if (common >= (wordsQ.size + 1) / 2) return true
        }
        return false
    }

    fun transliterate(text: String): String {
        val mapping = mapOf(
            'а' to "a", 'б' to "b", 'в' to "v", 'г' to "g", 'д' to "d",
            'е' to "e", 'ё' to "yo", 'ж' to "zh", 'з' to "z", 'и' to "i",
            'й' to "y", 'к' to "k", 'л' to "l", 'м' to "m", 'н' to "n",
            'о' to "o", 'п' to "p", 'р' to "r", 'с' to "s", 'т' to "t",
            'у' to "u", 'ф' to "f", 'х' to "kh", 'ц' to "ts", 'ч' to "ch",
            'ш' to "sh", 'щ' to "shch", 'ъ' to "", 'ы' to "y", 'ь' to "",
            'э' to "e", 'ю' to "yu", 'я' to "ya"
        )
        val sb = StringBuilder()
        for (c in text.lowercase()) {
            sb.append(mapping[c] ?: c.toString())
        }
        return sb.toString()
    }
}
