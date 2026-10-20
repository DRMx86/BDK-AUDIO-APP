package com.example.myspeaker.shared

/**
 * Platform interface for platform-specific implementations
 */
interface Platform {
    val name: String
}

expect fun getPlatform(): Platform
