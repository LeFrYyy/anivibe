package com.anivibe.app.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.ui.graphics.vector.ImageVector

sealed class Screen(val route: String, val title: String, val icon: ImageVector? = null) {
    object Home : Screen("home", "Главная", Icons.Default.Home)
    object Catalog : Screen("catalog", "Каталог", Icons.Default.GridView)
    object Library : Screen("library", "Библиотека", Icons.Default.Book)
    object Profile : Screen("profile", "Профиль", Icons.Default.Person)
    object Settings : Screen("settings", "Настройки")

    object Details : Screen("details/{animeId}", "Информация") {
        fun createRoute(animeId: Int): String = "details/$animeId"
    }

    object Player : Screen("player/{animeId}/{episode}?sourceKey={sourceKey}", "Плеер") {
        fun createRoute(animeId: Int, episode: Int, sourceKey: String? = null): String {
            return if (sourceKey != null) {
                "player/$animeId/$episode?sourceKey=$sourceKey"
            } else {
                "player/$animeId/$episode"
            }
        }
    }

    companion object {
        val bottomNavItems = listOf(Home, Catalog, Library, Profile)
    }
}
