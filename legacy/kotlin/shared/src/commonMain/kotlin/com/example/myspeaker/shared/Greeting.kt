package com.example.myspeaker.shared

/**
 * Greeting class for testing shared module connectivity
 */
class Greeting {
    private val platform = getPlatform()

    fun greet(): String {
        return "Hello from BDK Audio shared module on ${platform.name}!"
    }
}
