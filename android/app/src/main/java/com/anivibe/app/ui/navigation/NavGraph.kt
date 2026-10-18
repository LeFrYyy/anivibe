package com.anivibe.app.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import com.anivibe.app.AnivibeApplication
import com.anivibe.app.core.theme.BackgroundDark
import com.anivibe.app.core.theme.DefaultAccent
import com.anivibe.app.core.theme.SeparatorDark
import com.anivibe.app.core.theme.SurfaceDark
import com.anivibe.app.core.theme.TextPrimaryDark
import com.anivibe.app.core.theme.TextSecondaryDark
import com.anivibe.app.ui.components.tvFocusable
import com.anivibe.app.ui.screens.catalog.CatalogScreen
import com.anivibe.app.ui.screens.catalog.CatalogViewModel
import com.anivibe.app.ui.screens.details.AnimeDetailsScreen
import com.anivibe.app.ui.screens.details.AnimeDetailsViewModel
import com.anivibe.app.ui.screens.home.HomeScreen
import com.anivibe.app.ui.screens.home.HomeViewModel
import com.anivibe.app.ui.screens.library.LibraryScreen
import com.anivibe.app.ui.screens.library.LibraryViewModel
import com.anivibe.app.ui.screens.player.PlayerScreen
import com.anivibe.app.ui.screens.player.PlayerViewModel
import com.anivibe.app.ui.screens.profile.ProfileScreen
import com.anivibe.app.ui.screens.profile.ProfileViewModel
import com.anivibe.app.ui.screens.settings.SettingsScreen
import com.anivibe.app.ui.screens.settings.SettingsViewModel

@Composable
fun AnivibeNavGraph(
    app: AnivibeApplication,
    navController: NavHostController = rememberNavController(),
    modifier: Modifier = Modifier
) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    // Check if bottom bar should be visible (hidden in PlayerScreen and DetailsScreen)
    val isBottomBarVisible = currentRoute in Screen.bottomNavItems.map { it.route }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val isWideScreen = maxWidth >= 800.dp // Tablet landscape or Android TV

        if (isWideScreen && isBottomBarVisible) {
            // Adaptive Tablet / Android TV Layout with NavigationRail
            Row(modifier = Modifier.fillMaxSize()) {
                NavigationRail(
                    containerColor = SurfaceDark,
                    contentColor = TextPrimaryDark,
                    header = {
                        Text(
                            text = "Anivibe",
                            color = DefaultAccent,
                            style = MaterialTheme.typography.titleLarge,
                            modifier = Modifier.padding(vertical = 20.dp)
                        )
                    },
                    modifier = Modifier.width(90.dp)
                ) {
                    Screen.bottomNavItems.forEach { screen ->
                        val selected = currentRoute == screen.route
                        NavigationRailItem(
                            selected = selected,
                            onClick = {
                                if (currentRoute != screen.route) {
                                    navController.navigate(screen.route) {
                                        popUpTo(Screen.Home.route) { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            },
                            icon = { Icon(screen.icon!!, contentDescription = screen.title) },
                            label = { Text(screen.title, fontSize = 11.sp) },
                            colors = NavigationRailItemDefaults.colors(
                                selectedIconColor = Color.Black,
                                selectedTextColor = DefaultAccent,
                                indicatorColor = DefaultAccent,
                                unselectedIconColor = TextSecondaryDark,
                                unselectedTextColor = TextSecondaryDark
                            ),
                            modifier = Modifier.tvFocusable(cornerRadius = 12.dp, onClick = {
                                if (currentRoute != screen.route) {
                                    navController.navigate(screen.route) {
                                        popUpTo(Screen.Home.route) { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            })
                        )
                    }
                }

                Box(modifier = Modifier.weight(1f)) {
                    AppNavHost(app, navController)
                }
            }
        } else {
            // Mobile Phone Layout with Bottom NavigationBar
            Scaffold(
                bottomBar = {
                    if (isBottomBarVisible) {
                        NavigationBar(
                            containerColor = SurfaceDark,
                            contentColor = TextPrimaryDark
                        ) {
                            Screen.bottomNavItems.forEach { screen ->
                                val selected = currentRoute == screen.route
                                NavigationBarItem(
                                    selected = selected,
                                    onClick = {
                                        if (currentRoute != screen.route) {
                                            navController.navigate(screen.route) {
                                                popUpTo(Screen.Home.route) { saveState = true }
                                                launchSingleTop = true
                                                restoreState = true
                                            }
                                        }
                                    },
                                    icon = { Icon(screen.icon!!, contentDescription = screen.title) },
                                    label = { Text(screen.title, fontSize = 11.sp) },
                                    colors = NavigationBarItemDefaults.colors(
                                        selectedIconColor = Color.Black,
                                        selectedTextColor = DefaultAccent,
                                        indicatorColor = DefaultAccent,
                                        unselectedIconColor = TextSecondaryDark,
                                        unselectedTextColor = TextSecondaryDark
                                    ),
                                    modifier = Modifier.tvFocusable(cornerRadius = 12.dp, onClick = {
                                        if (currentRoute != screen.route) {
                                            navController.navigate(screen.route) {
                                                popUpTo(Screen.Home.route) { saveState = true }
                                                launchSingleTop = true
                                                restoreState = true
                                            }
                                        }
                                    })
                                )
                            }
                        }
                    }
                },
                containerColor = BackgroundDark
            ) { paddingValues ->
                Box(modifier = Modifier.padding(paddingValues)) {
                    AppNavHost(app, navController)
                }
            }
        }
    }
}

@Composable
fun AppNavHost(
    app: AnivibeApplication,
    navController: NavHostController
) {
    NavHost(
        navController = navController,
        startDestination = Screen.Home.route,
        modifier = Modifier.fillMaxSize()
    ) {
        composable(Screen.Home.route) {
            val viewModel = remember { HomeViewModel(app.catalogRepository, app.libraryRepository) }
            HomeScreen(
                viewModel = viewModel,
                onAnimeClick = { animeId -> navController.navigate(Screen.Details.createRoute(animeId)) },
                onContinueClick = { animeId, episode, sourceKey ->
                    navController.navigate(Screen.Player.createRoute(animeId, episode, sourceKey))
                }
            )
        }

        composable(Screen.Catalog.route) {
            val viewModel = remember { CatalogViewModel(app.catalogRepository) }
            CatalogScreen(
                viewModel = viewModel,
                onAnimeClick = { animeId -> navController.navigate(Screen.Details.createRoute(animeId)) }
            )
        }

        composable(Screen.Library.route) {
            val viewModel = remember { LibraryViewModel(app.libraryRepository) }
            LibraryScreen(
                viewModel = viewModel,
                onAnimeClick = { animeId -> navController.navigate(Screen.Details.createRoute(animeId)) }
            )
        }

        composable(Screen.Profile.route) {
            val viewModel = remember { ProfileViewModel(app.sessionRepository, app.libraryRepository) }
            ProfileScreen(
                viewModel = viewModel,
                onNavigateSettings = { navController.navigate(Screen.Settings.route) }
            )
        }

        composable(Screen.Settings.route) {
            val viewModel = remember { SettingsViewModel(app) }
            SettingsScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.Details.route,
            arguments = listOf(navArgument("animeId") { type = NavType.IntType })
        ) { backStackEntry ->
            val animeId = backStackEntry.arguments?.getInt("animeId") ?: return@composable
            val viewModel = remember(animeId) {
                AnimeDetailsViewModel(
                    animeId = animeId,
                    catalogRepository = app.catalogRepository,
                    videoSourceRepository = app.videoSourceRepository,
                    libraryRepository = app.libraryRepository
                )
            }
            AnimeDetailsScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onPlayEpisode = { aId, ep, srcKey ->
                    navController.navigate(Screen.Player.createRoute(aId, ep, srcKey))
                },
                onAnimeClick = { aId ->
                    navController.navigate(Screen.Details.createRoute(aId))
                }
            )
        }

        composable(
            route = Screen.Player.route,
            arguments = listOf(
                navArgument("animeId") { type = NavType.IntType },
                navArgument("episode") { type = NavType.IntType },
                navArgument("sourceKey") {
                    type = NavType.StringType
                    nullable = true
                    defaultValue = null
                }
            )
        ) { backStackEntry ->
            val animeId = backStackEntry.arguments?.getInt("animeId") ?: return@composable
            val episode = backStackEntry.arguments?.getInt("episode") ?: 1
            val sourceKey = backStackEntry.arguments?.getString("sourceKey")

            val viewModel = remember(animeId, episode, sourceKey) {
                PlayerViewModel(
                    animeId = animeId,
                    initialEpisode = episode,
                    initialSourceKey = sourceKey,
                    context = app,
                    catalogRepository = app.catalogRepository,
                    videoSourceRepository = app.videoSourceRepository,
                    libraryRepository = app.libraryRepository
                )
            }
            PlayerScreen(
                viewModel = viewModel,
                onClose = { navController.popBackStack() }
            )
        }
    }
}
