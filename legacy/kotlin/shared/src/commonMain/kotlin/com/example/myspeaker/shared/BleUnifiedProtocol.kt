package com.example.myspeaker.shared

/**
 * BLE Unified Protocol - Matches ESP32 ble_unified.h
 * 
 * Architecture:
 * - 1 Service with 3 characteristics
 * - CMD: Write commands to ESP32
 * - STATUS: Receive status notifications (settings, ACKs)
 * - METER: Receive real-time audio levels
 * 
 * This is cross-platform code shared between Android and iOS.
 */
object BleUnifiedProtocol {
    
    // ========== UUIDs (as strings for cross-platform compatibility) ==========
    const val SERVICE_UUID_STRING = "12345678-1234-1234-1234-123456789000"
    const val CHAR_CMD_UUID_STRING = "12345678-1234-1234-1234-123456789001"
    const val CHAR_STATUS_UUID_STRING = "12345678-1234-1234-1234-123456789002"
    const val CHAR_METER_UUID_STRING = "12345678-1234-1234-1234-123456789003"
    
    // CCCD for notifications
    const val CCCD_UUID_STRING = "00002902-0000-1000-8000-00805f9b34fb"
    
    // ========== Command IDs (Phone -> ESP32) ==========
    object Cmd {
        const val SET_EQ: Byte = 0x01           // [bass, mid, treble] 3 bytes signed
        const val SET_EQ_PRESET: Byte = 0x02    // [preset_id] 1 byte
        const val SET_CONTROL: Byte = 0x03      // [control_byte] 1 byte
        const val SET_NAME: Byte = 0x04         // [name...] 1-32 bytes
        const val SET_LED: Byte = 0x05          // [effect, bright, speed, r1,g1,b1, r2,g2,b2, gradient] 10 bytes
        const val SET_LED_EFFECT: Byte = 0x06   // [effect_id] 1 byte
        const val SET_LED_BRIGHT: Byte = 0x07   // [brightness] 1 byte
        
        const val SOUND_MUTE: Byte = 0x10       // [0/1] 1 byte
        const val SOUND_DELETE: Byte = 0x11    // [type] 1 byte
        const val SOUND_UP_START: Byte = 0x12  // [type, size_lo, size_mid, size_hi] 4 bytes
        const val SOUND_UP_DATA: Byte = 0x13   // [seq, data...] 1+N bytes
        const val SOUND_UP_END: Byte = 0x14    // no payload
        
        const val OTA_BEGIN: Byte = 0x20        // [size_lo, size_mid, size_hi, size_hhi] 4 bytes
        const val OTA_DATA: Byte = 0x21         // [seq, data...] 1+N bytes
        const val OTA_END: Byte = 0x22          // no payload
        const val OTA_ABORT: Byte = 0x23        // no payload
        
        const val REQUEST_STATUS: Byte = 0xF0.toByte()  // no payload - request full sync
        const val PING: Byte = 0xFF.toByte()            // no payload
    }
    
    // ========== Response IDs (ESP32 -> Phone) ==========
    object Resp {
        const val STATUS_EQ: Byte = 0x01        // [bass, mid, treble] 3 bytes
        const val STATUS_CONTROL: Byte = 0x02   // [control_byte] 1 byte
        const val STATUS_NAME: Byte = 0x03      // [name...] 1-32 bytes
        const val STATUS_FW: Byte = 0x04        // [version...] string
        const val STATUS_LED: Byte = 0x05       // [effect, bright, speed, r1,g1,b1, r2,g2,b2, gradient] 10 bytes
        const val STATUS_SOUND: Byte = 0x06     // [status_byte] 1 byte
        
        const val ACK_OK: Byte = 0x10           // [cmd] 1 byte
        const val ACK_ERROR: Byte = 0x11        // [cmd, error_code] 2 bytes
        
        const val OTA_PROGRESS: Byte = 0x20     // [percent] 1 byte
        const val OTA_READY: Byte = 0x21        // no payload - ready for next chunk
        const val OTA_COMPLETE: Byte = 0x22     // no payload
        const val OTA_FAILED: Byte = 0x23       // [error_code] 1 byte
        
        const val SOUND_PROGRESS: Byte = 0x30   // [percent] 1 byte
        const val SOUND_READY: Byte = 0x31      // no payload - ready for next chunk
        const val SOUND_COMPLETE: Byte = 0x32   // no payload
        const val SOUND_FAILED: Byte = 0x33     // [error_code] 1 byte
        
        const val FULL_STATUS: Byte = 0xF0.toByte()  // full status dump
        const val PONG: Byte = 0xFF.toByte()         // ping response
    }
    
    // ========== Error codes ==========
    object Error {
        const val NONE: Byte = 0x00
        const val INVALID_CMD: Byte = 0x01
        const val INVALID_PARAM: Byte = 0x02
        const val BUSY: Byte = 0x03
        const val OTA_INIT_FAIL: Byte = 0x10
        const val OTA_WRITE_FAIL: Byte = 0x11
        const val OTA_VERIFY_FAIL: Byte = 0x12
        const val SOUND_INIT_FAIL: Byte = 0x20
        const val SOUND_WRITE_FAIL: Byte = 0x21
    }
    
    // ========== EQ Presets (matches ESP32) ==========
    val EQ_PRESETS = arrayOf(
        "Flat",
        "Bass Boost",
        "Treble Boost",
        "Vocal",
        "Rock",
        "Pop",
        "Jazz",
        "Classical",
        "Electronic",
        "Hip Hop",
        "Acoustic",
        "Loudness"
    )
    
    val EQ_PRESET_VALUES = arrayOf(
        intArrayOf(0, 0, 0),      // Flat
        intArrayOf(6, 2, 0),      // Bass Boost
        intArrayOf(0, 2, 6),      // Treble Boost
        intArrayOf(-2, 4, 2),     // Vocal
        intArrayOf(4, 0, 4),      // Rock
        intArrayOf(2, 3, 4),      // Pop
        intArrayOf(3, 0, 2),      // Jazz
        intArrayOf(0, 2, 3),      // Classical
        intArrayOf(5, 2, 4),      // Electronic
        intArrayOf(6, 0, 2),      // Hip Hop
        intArrayOf(2, 3, 3),      // Acoustic
        intArrayOf(4, 2, 4)       // Loudness
    )
    
    // ========== Command Builders ==========
    
    fun buildSetEq(bass: Int, mid: Int, treble: Int): ByteArray {
        return byteArrayOf(Cmd.SET_EQ, bass.toByte(), mid.toByte(), treble.toByte())
    }
    
    fun buildSetEqPreset(presetId: Int): ByteArray {
        return byteArrayOf(Cmd.SET_EQ_PRESET, presetId.toByte())
    }
    
    fun buildSetControl(controlByte: Int): ByteArray {
        return byteArrayOf(Cmd.SET_CONTROL, controlByte.toByte())
    }
    
    fun buildSetName(name: String): ByteArray {
        val nameBytes = name.encodeToByteArray().take(32).toByteArray()
        return byteArrayOf(Cmd.SET_NAME) + nameBytes
    }
    
    fun buildSetLed(
        effectId: Int,
        brightness: Int,
        speed: Int,
        r1: Int, g1: Int, b1: Int,
        r2: Int, g2: Int, b2: Int,
        gradient: Int
    ): ByteArray {
        // Send 0-100 directly - ESP32 handles conversion to 0-255
        return byteArrayOf(
            Cmd.SET_LED,
            effectId.toByte(),
            brightness.coerceIn(0, 100).toByte(),
            speed.coerceIn(0, 100).toByte(),
            r1.toByte(), g1.toByte(), b1.toByte(),
            r2.toByte(), g2.toByte(), b2.toByte(),
            gradient.toByte()
        )
    }
    
    fun buildSetLedEffect(effectId: Int): ByteArray {
        return byteArrayOf(Cmd.SET_LED_EFFECT, effectId.toByte())
    }
    
    fun buildSetLedBrightness(brightness: Int): ByteArray {
        // Send 0-100 directly - ESP32 handles conversion to 0-255
        return byteArrayOf(Cmd.SET_LED_BRIGHT, brightness.coerceIn(0, 100).toByte())
    }
    
    fun buildSoundMute(muted: Boolean): ByteArray {
        return byteArrayOf(Cmd.SOUND_MUTE, if (muted) 1 else 0)
    }
    
    fun buildSoundDelete(soundType: Int): ByteArray {
        return byteArrayOf(Cmd.SOUND_DELETE, soundType.toByte())
    }
    
    fun buildSoundUploadStart(soundType: Int, size: Int): ByteArray {
        return byteArrayOf(
            Cmd.SOUND_UP_START,
            soundType.toByte(),
            (size and 0xFF).toByte(),
            ((size shr 8) and 0xFF).toByte(),
            ((size shr 16) and 0xFF).toByte()
        )
    }
    
    fun buildSoundUploadData(seq: Int, data: ByteArray): ByteArray {
        return byteArrayOf(Cmd.SOUND_UP_DATA, seq.toByte()) + data
    }
    
    fun buildSoundUploadEnd(): ByteArray {
        return byteArrayOf(Cmd.SOUND_UP_END)
    }
    
    fun buildOtaBegin(size: Int): ByteArray {
        return byteArrayOf(
            Cmd.OTA_BEGIN,
            (size and 0xFF).toByte(),
            ((size shr 8) and 0xFF).toByte(),
            ((size shr 16) and 0xFF).toByte(),
            ((size shr 24) and 0xFF).toByte()
        )
    }
    
    fun buildOtaData(seq: Int, data: ByteArray): ByteArray {
        return byteArrayOf(Cmd.OTA_DATA, seq.toByte()) + data
    }
    
    fun buildOtaEnd(): ByteArray {
        return byteArrayOf(Cmd.OTA_END)
    }
    
    fun buildOtaAbort(): ByteArray {
        return byteArrayOf(Cmd.OTA_ABORT)
    }
    
    fun buildRequestStatus(): ByteArray {
        return byteArrayOf(Cmd.REQUEST_STATUS)
    }
    
    fun buildPing(): ByteArray {
        return byteArrayOf(Cmd.PING)
    }
    
    // ========== Response Parsers ==========
    
    data class StatusEq(val bass: Int, val mid: Int, val treble: Int)
    data class StatusLed(
        val effectId: Int,
        val brightness: Int,
        val speed: Int,
        val r1: Int, val g1: Int, val b1: Int,
        val r2: Int, val g2: Int, val b2: Int,
        val gradient: Int
    )
    data class FullStatus(
        val eq: StatusEq,
        val controlByte: Int,
        val led: StatusLed,
        val soundStatus: Int,
        val deviceName: String,
        val firmwareVersion: String
    )
    
    fun parseStatusEq(data: ByteArray): StatusEq? {
        if (data.size < 3) return null
        return StatusEq(
            bass = data[0].toInt(),
            mid = data[1].toInt(),
            treble = data[2].toInt()
        )
    }
    
    fun parseStatusLed(data: ByteArray): StatusLed? {
        if (data.size < 10) return null
        // ESP32 already sends brightness/speed as 0-100
        val brightness = data[1].toInt() and 0xFF
        val speed = data[2].toInt() and 0xFF
        return StatusLed(
            effectId = data[0].toInt() and 0xFF,
            brightness = brightness.coerceIn(0, 100),
            speed = speed.coerceIn(0, 100),
            r1 = data[3].toInt() and 0xFF,
            g1 = data[4].toInt() and 0xFF,
            b1 = data[5].toInt() and 0xFF,
            r2 = data[6].toInt() and 0xFF,
            g2 = data[7].toInt() and 0xFF,
            b2 = data[8].toInt() and 0xFF,
            gradient = data[9].toInt() and 0xFF
        )
    }
    
    fun parseFullStatus(data: ByteArray): FullStatus? {
        // Format: [bass, mid, treble, control, led[10], sound, name_len, name..., fw_len, fw...]
        if (data.size < 16) return null  // Minimum: 3+1+10+1+1 = 16
        
        var idx = 0
        
        // EQ (3 bytes)
        val eq = StatusEq(
            bass = data[idx++].toInt(),
            mid = data[idx++].toInt(),
            treble = data[idx++].toInt()
        )
        
        // Control (1 byte)
        val controlByte = data[idx++].toInt() and 0xFF
        
        // LED (10 bytes) - ESP32 already sends brightness/speed as 0-100
        val ledEffectId = data[idx++].toInt() and 0xFF
        val ledBrightness = data[idx++].toInt() and 0xFF  // Already 0-100 from ESP32
        val ledSpeed = data[idx++].toInt() and 0xFF       // Already 0-100 from ESP32
        val led = StatusLed(
            effectId = ledEffectId,
            brightness = ledBrightness.coerceIn(0, 100),
            speed = ledSpeed.coerceIn(0, 100),
            r1 = data[idx++].toInt() and 0xFF,
            g1 = data[idx++].toInt() and 0xFF,
            b1 = data[idx++].toInt() and 0xFF,
            r2 = data[idx++].toInt() and 0xFF,
            g2 = data[idx++].toInt() and 0xFF,
            b2 = data[idx++].toInt() and 0xFF,
            gradient = data[idx++].toInt() and 0xFF
        )
        
        // Sound status (1 byte)
        val soundStatus = data[idx++].toInt() and 0xFF
        
        // Device name (length + string)
        if (idx >= data.size) return null
        val nameLen = data[idx++].toInt() and 0xFF
        if (idx + nameLen > data.size) return null
        val deviceName = data.sliceArray(idx until idx + nameLen).decodeToString()
        idx += nameLen
        
        // Firmware version (length + string)
        if (idx >= data.size) return null
        val fwLen = data[idx++].toInt() and 0xFF
        if (idx + fwLen > data.size) return null
        val firmwareVersion = data.sliceArray(idx until idx + fwLen).decodeToString()
        
        return FullStatus(
            eq = eq,
            controlByte = controlByte,
            led = led,
            soundStatus = soundStatus,
            deviceName = deviceName,
            firmwareVersion = firmwareVersion
        )
    }
}
