package com.example.myspeaker.shared

/**
 * Sound types for custom sounds on the speaker
 */
enum class SoundType(val id: Int, val displayName: String, val description: String) {
    STARTUP(0, "Startup", "Played when speaker powers on"),
    PAIRING(1, "Pairing", "Played when entering pairing mode"),
    CONNECTED(2, "Connected", "Played when device connects"),
    MAX_VOLUME(3, "Max Volume", "Played at maximum volume warning");
    
    companion object {
        fun fromId(id: Int): SoundType? = entries.find { it.id == id }
    }
}

/**
 * Control byte flags (matches ESP32)
 */
object ControlFlags {
    const val BASS_BOOST: Int = 0x01      // Bit 0: Bass boost enabled
    const val BYPASS_DSP: Int = 0x02      // Bit 1: Bypass DSP processing
    const val CHANNEL_FLIP: Int = 0x04    // Bit 2: Swap L/R channels
    const val TWS_MASTER: Int = 0x08      // Bit 3: TWS master mode
    const val TWS_SLAVE: Int = 0x10       // Bit 4: TWS slave mode
    const val MUTE: Int = 0x20            // Bit 5: Audio muted
    
    fun isBassBoostEnabled(controlByte: Int): Boolean = (controlByte and BASS_BOOST) != 0
    fun isBypassDspEnabled(controlByte: Int): Boolean = (controlByte and BYPASS_DSP) != 0
    fun isChannelFlipEnabled(controlByte: Int): Boolean = (controlByte and CHANNEL_FLIP) != 0
    fun isTwsMaster(controlByte: Int): Boolean = (controlByte and TWS_MASTER) != 0
    fun isTwsSlave(controlByte: Int): Boolean = (controlByte and TWS_SLAVE) != 0
    fun isMuted(controlByte: Int): Boolean = (controlByte and MUTE) != 0
    
    fun buildControlByte(
        bassBoost: Boolean = false,
        bypassDsp: Boolean = false,
        channelFlip: Boolean = false,
        twsMaster: Boolean = false,
        twsSlave: Boolean = false,
        mute: Boolean = false
    ): Int {
        var byte = 0
        if (bassBoost) byte = byte or BASS_BOOST
        if (bypassDsp) byte = byte or BYPASS_DSP
        if (channelFlip) byte = byte or CHANNEL_FLIP
        if (twsMaster) byte = byte or TWS_MASTER
        if (twsSlave) byte = byte or TWS_SLAVE
        if (mute) byte = byte or MUTE
        return byte
    }
}

/**
 * Codec types for Bluetooth audio
 */
enum class AudioCodec(val displayName: String, val description: String) {
    SBC("SBC", "Standard Bluetooth codec"),
    AAC("AAC", "Apple Audio Codec"),
    APTX("aptX", "Qualcomm aptX"),
    APTX_HD("aptX HD", "Qualcomm aptX HD (24-bit)"),
    LDAC("LDAC", "Sony LDAC (Hi-Res)");
    
    companion object {
        fun fromName(name: String): AudioCodec? = entries.find { 
            it.displayName.equals(name, ignoreCase = true) ||
            it.name.equals(name, ignoreCase = true)
        }
    }
}
