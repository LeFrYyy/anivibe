package com.anivibe.app.core.network

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.header
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import java.util.concurrent.TimeUnit

object HttpClientFactory {

    val jsonInstance = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        coerceInputValues = true
    }

    fun create(): HttpClient {
        return HttpClient(OkHttp) {
            engine {
                config {
                    connectTimeout(20, TimeUnit.SECONDS)
                    readTimeout(30, TimeUnit.SECONDS)
                    writeTimeout(20, TimeUnit.SECONDS)
                    followRedirects(true)
                }
            }
            install(ContentNegotiation) {
                json(jsonInstance)
            }
            defaultRequest {
                header("User-Agent", "Anivibe-Android/1.0 (Linux; Android)")
            }
        }
    }
}
