package com.anivibe.app.ui.components

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

object AdaptiveGridHelper {

    @Composable
    fun getAdaptiveColumns(minWidth: Dp = 140.dp): GridCells {
        return GridCells.Adaptive(minSize = minWidth)
    }

    fun calculateColumnCount(widthDp: Dp): Int {
        return when {
            widthDp < 400.dp -> 2
            widthDp < 600.dp -> 3
            widthDp < 840.dp -> 4
            widthDp < 1200.dp -> 5
            else -> 6
        }
    }
}
