package com.anivibe.app.core.network

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class RateLimiter(
    private val maxTokens: Int,
    private val perPeriodMillis: Long
) {
    private val mutex = Mutex()
    private val timestamps = ArrayDeque<Long>()

    suspend fun acquire() {
        mutex.withLock {
            val now = System.currentTimeMillis()
            while (timestamps.isNotEmpty() && now - timestamps.first() > perPeriodMillis) {
                timestamps.removeFirst()
            }
            if (timestamps.size >= maxTokens) {
                val waitTime = perPeriodMillis - (now - timestamps.first())
                if (waitTime > 0) {
                    delay(waitTime)
                }
                while (timestamps.isNotEmpty() && System.currentTimeMillis() - timestamps.first() > perPeriodMillis) {
                    timestamps.removeFirst()
                }
            }
            timestamps.addLast(System.currentTimeMillis())
        }
    }
}
