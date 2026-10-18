package com.anivibe.app

import android.app.Application
import android.content.Context
import com.anivibe.app.core.network.HttpClientFactory
import com.anivibe.app.data.local.AnivibeDatabase
import com.anivibe.app.data.remote.anilibria.AnilibriaService
import com.anivibe.app.data.remote.anilist.AniListService
import com.anivibe.app.data.remote.kodik.KodikService
import com.anivibe.app.data.remote.shikimori.ShikimoriService
import com.anivibe.app.data.remote.supabase.SupabaseAuthService
import com.anivibe.app.data.remote.supabase.SupabaseRestService
import com.anivibe.app.data.remote.supabase.SupabaseSyncManager
import com.anivibe.app.data.repository.CatalogRepository
import com.anivibe.app.data.repository.LibraryRepository
import com.anivibe.app.data.repository.SessionRepository
import com.anivibe.app.data.repository.VideoSourceRepository

class AnivibeApplication : Application() {

    lateinit var database: AnivibeDatabase
        private set

    lateinit var catalogRepository: CatalogRepository
        private set

    lateinit var videoSourceRepository: VideoSourceRepository
        private set

    lateinit var libraryRepository: LibraryRepository
        private set

    lateinit var sessionRepository: SessionRepository
        private set

    lateinit var syncManager: SupabaseSyncManager
        private set

    override fun onCreate() {
        super.onCreate()

        // 1. Local Database
        database = AnivibeDatabase.getDatabase(this)

        // 2. HTTP Engine
        val httpClient = HttpClientFactory.create()

        // 3. Remote Services
        val aniListService = AniListService(httpClient)
        val shikimoriService = ShikimoriService(httpClient)

        val settingsPrefs = getSharedPreferences("anivibe_settings", Context.MODE_PRIVATE)
        val tokenProvider = {
            val userToken = settingsPrefs.getString("kodik_token", "")?.trim()
            if (!userToken.isNullOrEmpty()) userToken else BuildConfig.KODIK_TOKEN
        }
        val kodikService = KodikService(httpClient, tokenProvider)
        val anilibriaService = AnilibriaService(httpClient)

        val supabaseAuth = SupabaseAuthService(
            client = httpClient,
            supabaseUrl = BuildConfig.SUPABASE_URL,
            anonKey = BuildConfig.SUPABASE_ANON_KEY,
            context = this
        )
        val supabaseRest = SupabaseRestService(
            client = httpClient,
            supabaseUrl = BuildConfig.SUPABASE_URL,
            anonKey = BuildConfig.SUPABASE_ANON_KEY
        )

        // 4. Repositories
        catalogRepository = CatalogRepository(aniListService, shikimoriService)
        videoSourceRepository = VideoSourceRepository(kodikService, anilibriaService)
        libraryRepository = LibraryRepository(database)

        syncManager = SupabaseSyncManager(database, supabaseAuth, supabaseRest)
        sessionRepository = SessionRepository(supabaseAuth, syncManager)
    }
}
