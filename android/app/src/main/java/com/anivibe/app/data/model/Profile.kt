package com.anivibe.app.data.model

import kotlinx.serialization.Serializable

@Serializable
data class AnimeCollection(
    val id: String, // UUID
    val name: String,
    val emoji: String = "📁",
    val animeIds: List<Int> = emptyList(),
    val displayOrder: Int = 0,
    val updatedAt: Long = System.currentTimeMillis()
)

@Serializable
data class UserProfile(
    val id: String,
    val email: String? = null,
    val username: String? = null,
    val displayName: String? = null,
    val bio: String? = null,
    val avatarUrl: String? = null,
    val bannerUrl: String? = null,
    val isPrivate: Boolean = false,
    val friendsVisibility: String = "friends",
    val historyVisibility: String = "friends",
    val libraryVisibility: String = "friends"
)

@Serializable
data class UserStats(
    val watching: Int = 0,
    val completed: Int = 0,
    val planned: Int = 0,
    val onHold: Int = 0,
    val dropped: Int = 0,
    val favorites: Int = 0,
    val totalTitles: Int = 0
)

@Serializable
data class Friend(
    val userId: String,
    val displayName: String?,
    val username: String?,
    val avatarUrl: String?,
    val status: String = "accepted"
)
