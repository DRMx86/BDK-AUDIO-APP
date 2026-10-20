package com.example.myspeaker.shared

/**
 * LED Effect types that match ESP32 led_config.h LedEffectId enum
 */
enum class LedEffect(val id: Int, val displayName: String, val emoji: String) {
    SPECTRUM_BARS(0, "Spectrum Bars", "📊"),
    BEAT_PULSE(1, "Beat Pulse", "💓"),
    RIPPLE(2, "Ripple", "🌊"),
    FIRE(3, "Fire", "🔥"),
    PLASMA(4, "Plasma", "🟣"),
    MATRIX_RAIN(5, "Matrix Rain", "💚"),
    VU_METER(6, "VU Meter", "📶"),
    STARFIELD(7, "Starfield", "⭐"),
    WAVE(8, "Wave", "〰️"),
    FIREWORKS(9, "Fireworks", "🎆"),
    RAINBOW_WAVE(10, "Rainbow Wave", "🌈"),
    PARTICLE_BURST(11, "Particle Burst", "💥"),
    KALEIDOSCOPE(12, "Kaleidoscope", "🔮"),
    FREQUENCY_SPIRAL(13, "Frequency Spiral", "🌀"),
    BASS_REACTOR(14, "Bass Reactor", "🎵"),
    METEOR_SHOWER(15, "Meteor Shower", "☄️"),
    BREATHING(16, "Breathing", "💨"),
    DNA_HELIX(17, "DNA Helix", "🧬"),
    AUDIO_SCOPE(18, "Audio Scope", "📈"),
    BOUNCING_BALLS(19, "Bouncing Balls", "⚽"),
    LAVA_LAMP(20, "Lava Lamp", "🫧"),
    AMBIENT(21, "Ambient", "✨"),
    OFF(255, "Off", "⭕");
    
    companion object {
        // All user-selectable effects (excludes OFF which is handled separately)
        val userEffects: List<LedEffect> = entries.filter { it != OFF }
        
        // Quick select effects (shown as grid buttons like Android)
        val quickSelectEffects = listOf(
            SPECTRUM_BARS,  // "Spectrum"
            BEAT_PULSE,     // "Beat Pulse"
            BASS_REACTOR,   // "Bass"
            RAINBOW_WAVE,   // "Rainbow"
            AMBIENT,        // "Ambient"
            OFF             // "Off"
        )
        
        fun fromId(id: Int): LedEffect = entries.find { it.id == id } ?: SPECTRUM_BARS
        
        // Effects that show speed control
        val speedEffects = listOf(
            SPECTRUM_BARS, BEAT_PULSE, RIPPLE, FIRE, PLASMA, MATRIX_RAIN,
            VU_METER, STARFIELD, WAVE, FIREWORKS, RAINBOW_WAVE, PARTICLE_BURST,
            KALEIDOSCOPE, FREQUENCY_SPIRAL, BASS_REACTOR, METEOR_SHOWER,
            BREATHING, DNA_HELIX, AUDIO_SCOPE, BOUNCING_BALLS, LAVA_LAMP, AMBIENT
        )
        
        // Only Ambient shows full color/gradient controls
        val colorControlEffects = listOf(AMBIENT)
    }
}

/**
 * Gradient types for Ambient effect - matches ESP32 LedGradientType
 */
enum class GradientType(val id: Int, val displayName: String) {
    NONE(0, "None"),
    LINEAR_H(1, "Horizontal"),
    LINEAR_V(2, "Vertical"),
    RADIAL(3, "Radial"),
    DIAGONAL(4, "Diagonal");
    
    companion object {
        fun fromId(id: Int): GradientType = entries.find { it.id == id } ?: NONE
    }
}
