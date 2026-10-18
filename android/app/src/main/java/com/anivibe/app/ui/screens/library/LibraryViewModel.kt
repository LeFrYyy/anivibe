package com.anivibe.app.ui.screens.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.anivibe.app.data.model.LibraryEntry
import com.anivibe.app.data.model.LibraryStatus
import com.anivibe.app.data.model.WatchHistoryItem
import com.anivibe.app.data.repository.LibraryRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class LibraryTab(val title: String) {
    WATCHING("Смотрю"),
    COMPLETED("Просмотрено"),
    PLANNED("Запланировано"),
    ON_HOLD("Отложено"),
    DROPPED("Брошено"),
    FAVORITES("Избранное"),
    HISTORY("История")
}

class LibraryViewModel(
    private val libraryRepository: LibraryRepository
) : ViewModel() {

    private val _selectedTab = MutableStateFlow(LibraryTab.WATCHING)
    val selectedTab: StateFlow<LibraryTab> = _selectedTab.asStateFlow()

    val watchingList = libraryRepository.getEntriesByStatus(LibraryStatus.WATCHING)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val completedList = libraryRepository.getEntriesByStatus(LibraryStatus.COMPLETED)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val plannedList = libraryRepository.getEntriesByStatus(LibraryStatus.PLANNED)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val onHoldList = libraryRepository.getEntriesByStatus(LibraryStatus.ON_HOLD)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val droppedList = libraryRepository.getEntriesByStatus(LibraryStatus.DROPPED)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val favoritesList = libraryRepository.getFavorites()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val historyList = libraryRepository.observeHistory()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun selectTab(tab: LibraryTab) {
        _selectedTab.value = tab
    }

    fun clearHistory() {
        viewModelScope.launch {
            libraryRepository.clearHistory()
        }
    }
}
