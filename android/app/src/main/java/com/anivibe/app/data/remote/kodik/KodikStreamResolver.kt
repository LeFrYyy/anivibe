package com.anivibe.app.data.remote.kodik

import com.anivibe.app.core.util.CaesarCipher
import com.anivibe.app.data.model.KodikStream
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.forms.formData
import io.ktor.client.request.forms.submitForm
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Parameters
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI

class KodikStreamResolver(
    private val client: HttpClient
) {
    private val userAgent = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"

    data class PlayerInfo(
        val type: String,
        val hash: String,
        val id: String,
        val params: Map<String, String>
    )

    suspend fun resolveStreams(rawPlayerUrl: String): List<KodikStream> {
        val playerUrl = if (rawPlayerUrl.startsWith("//")) "https:$rawPlayerUrl" else rawPlayerUrl
        val uri = URI(playerUrl)
        val host = uri.host ?: return emptyList()
        val origin = "https://$host"

        val pageHtml: String = client.get(playerUrl) {
            header("User-Agent", userAgent)
        }.bodyAsText()

        val playerInfo = parsePlayerPage(pageHtml) ?: return emptyList()

        var endpoint = "/ftor"
        val scriptPath = parsePlayerScriptPath(pageHtml)
        if (scriptPath != null) {
            val fullScriptUrl = if (scriptPath.startsWith("http")) scriptPath else "$origin$scriptPath"
            try {
                val scriptText: String = client.get(fullScriptUrl) {
                    header("User-Agent", userAgent)
                    header("Referer", playerUrl)
                }.bodyAsText()
                val foundEndpoint = parseEndpointFromScript(scriptText)
                if (foundEndpoint != null) {
                    endpoint = foundEndpoint
                }
            } catch (e: Exception) {
                // fallback to default /ftor
            }
        }

        val apiEndpoint = if (endpoint.startsWith("http")) endpoint else "$origin$endpoint"

        val formParams = Parameters.build {
            append("type", playerInfo.type)
            append("hash", playerInfo.hash)
            append("id", playerInfo.id)
            append("bad_user", "true")
            append("cdn_is_working", "true")
            append("info", "{}")
            for ((k, v) in playerInfo.params) {
                append(k, v)
            }
        }

        val responseText: String = client.submitForm(
            url = apiEndpoint,
            formParameters = formParams
        ) {
            header("User-Agent", userAgent)
            header("Referer", playerUrl)
            header("Origin", origin)
            header("X-Requested-With", "XMLHttpRequest")
            header("Accept", "application/json, text/javascript, */*; q=0.01")
        }.bodyAsText()

        return parseLinks(responseText)
    }

    private fun parsePlayerPage(html: String): PlayerInfo? {
        val type = Regex("""(?:vInfo|videoInfo)\.type\s*=\s*['"]([^'"]+)['"]""").find(html)?.groupValues?.get(1) ?: return null
        val hash = Regex("""(?:vInfo|videoInfo)\.hash\s*=\s*['"]([^'"]+)['"]""").find(html)?.groupValues?.get(1) ?: return null
        val id = Regex("""(?:vInfo|videoInfo)\.id\s*=\s*['"]([^'"]+)['"]""").find(html)?.groupValues?.get(1) ?: return null

        val params = mutableMapOf<String, String>()
        val urlParamsJson = Regex("""urlParams\s*=\s*'([^']*)'""").find(html)?.groupValues?.get(1)
        if (urlParamsJson != null) {
            try {
                val jsonObject = Json.parseToJsonElement(urlParamsJson).jsonObject
                for (key in listOf("d", "d_sign", "pd", "pd_sign", "ref", "ref_sign")) {
                    jsonObject[key]?.jsonPrimitive?.content?.let {
                        params[key] = it
                    }
                }
            } catch (e: Exception) {
                // Ignore parse errors
            }
        }
        return PlayerInfo(type, hash, id, params)
    }

    private fun parsePlayerScriptPath(html: String): String? {
        return Regex("""src=["']([^"']*app\.player_single[^"']*\.js)["']""").find(html)?.groupValues?.get(1)
    }

    private fun parseEndpointFromScript(script: String): String? {
        val encoded = Regex("""type:\s*"POST",\s*url:\s*atob\("([^"]+)"\)""").find(script)?.groupValues?.get(1) ?: return null
        val decoded = CaesarCipher.base64Decode(encoded)
        return if (decoded?.startsWith("/") == true) decoded else null
    }

    private fun parseLinks(jsonText: String): List<KodikStream> {
        return try {
            val root = Json.parseToJsonElement(jsonText).jsonObject
            val links = root["links"]?.jsonObject ?: return emptyList()
            val streams = mutableListOf<KodikStream>()

            for ((declaredQualityKey, value) in links) {
                val declaredQuality = declaredQualityKey.toIntOrNull() ?: continue
                val items = value.jsonArray
                val firstItem = items.firstOrNull()?.jsonObject ?: continue
                val src = firstItem["src"]?.jsonPrimitive?.content ?: continue
                val decodedLink = CaesarCipher.decodeKodikSource(src) ?: continue
                val normalizedUrl = if (decodedLink.startsWith("//")) "https:$decodedLink" else decodedLink

                val actualQuality = Regex("""/(\d{3,4})\.mp4""").find(normalizedUrl)?.groupValues?.get(1)?.toIntOrNull()
                    ?: declaredQuality

                streams.add(KodikStream(actualQuality, normalizedUrl))
            }

            streams.distinctBy { it.quality }.sortedByDescending { it.quality }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
