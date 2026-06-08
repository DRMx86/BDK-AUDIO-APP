package com.example.myspeaker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothCodecConfig
import android.bluetooth.BluetoothDevice
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.lang.reflect.InvocationTargetException

/**
 * Self-contained Bluetooth A2DP codec controller.
 *
 * Mirrors the proven approach used by the "Bluetooth Codec Changer" app:
 *  - getCodecStatus / setCodecConfigPreference via reflection (only needs BLUETOOTH_CONNECT)
 *  - reads codec details by parsing BluetoothCodecConfig.toString() (robust across OEMs)
 *  - builds configs via the 9-arg legacy constructor (with Builder fallback)
 *  - applies in two steps when codecSpecific1 != 0 (e.g. LDAC quality)
 */
@Suppress("DEPRECATION")
object CodecManager {

    private const val TAG = "BT/Codec"
    private val handler = Handler(Looper.getMainLooper())

    // ---- Codec type constants (stable AOSP values) ----
    const val TYPE_SBC = 0
    const val TYPE_AAC = 1
    const val TYPE_APTX = 2
    const val TYPE_APTX_HD = 3
    const val TYPE_LDAC = 4
    const val TYPE_OPUS = 6

    private const val PRIORITY_HIGHEST = 1_000_000

    // ---- Sample rate bitmask values ----
    const val SR_44100 = 0x1
    const val SR_48000 = 0x2
    const val SR_88200 = 0x4
    const val SR_96000 = 0x8
    const val SR_176400 = 0x10
    const val SR_192000 = 0x20

    // ---- Bits-per-sample bitmask values ----
    const val BPS_16 = 0x1
    const val BPS_24 = 0x2
    const val BPS_32 = 0x4

    // ---- Channel mode bitmask values ----
    const val CH_MONO = 0x1
    const val CH_STEREO = 0x2

    // Last-known data captured from CODEC_CONFIG_CHANGED broadcasts. This survives across
    // screens and is the reliable source on devices (e.g. Samsung) where getCodecStatus()
    // returns null for non-privileged apps but the broadcast still delivers a full status.
    @Volatile
    var cachedAudioInfo: AudioInfo? = null
        private set

    @Volatile
    var cachedCapabilities: List<CodecCapability> = emptyList()
        private set

    /** Parsed snapshot of the current codec configuration. */
    data class AudioInfo(
        val codecType: Int,
        val codecName: String,
        val sampleRateMask: Int,
        val bitsPerSampleMask: Int,
        val channelModeMask: Int,
        val codecSpecific1: Long
    ) {
        val sampleRateLabel: String get() = sampleRateLabel(sampleRateMask)
        val bitsPerSampleLabel: String get() = bitsLabel(bitsPerSampleMask)
        val channelModeLabel: String get() = channelLabel(channelModeMask)
    }

    /** Capabilities (supported sample rates / bits) for a single selectable codec. */
    data class CodecCapability(
        val codecType: Int,
        val codecName: String,
        val sampleRateMask: Int,
        val bitsPerSampleMask: Int,
        val channelModeMask: Int,
        val codecSpecific1: Long
    )

    // =====================================================================
    // Reading
    // =====================================================================

    @SuppressLint("MissingPermission")
    fun getCodecStatus(a2dp: BluetoothA2dp?, device: BluetoothDevice?): Any? {
        if (a2dp == null || device == null) {
            Log.w(TAG, "getCodecStatus skipped: a2dp=${a2dp != null}, device=${device?.address}")
            return null
        }
        return try {
            val m = a2dp.javaClass.getMethod("getCodecStatus", BluetoothDevice::class.java)
            val status = m.invoke(a2dp, device)
            Log.d(TAG, "getCodecStatus(${device.address}) -> $status")
            status
        } catch (e: InvocationTargetException) {
            Log.w(TAG, "getCodecStatus failed: ${e.cause?.message}")
            null
        } catch (e: SecurityException) {
            Log.w(TAG, "getCodecStatus SecurityException: ${e.message}")
            null
        } catch (e: Exception) {
            Log.w(TAG, "getCodecStatus error: ${e.message}")
            null
        }
    }

    /** Reads the currently active codec config, falling back to the cached broadcast value. */
    fun getCurrentAudioInfo(a2dp: BluetoothA2dp?, device: BluetoothDevice?): AudioInfo? {
        val status = getCodecStatus(a2dp, device) ?: return cachedAudioInfo
        val config = invokeNoArg(status, "getCodecConfig") ?: return cachedAudioInfo
        val info = parseConfig(config)
        if (info != null) cachedAudioInfo = info
        return info ?: cachedAudioInfo
    }

    /** Enumerates the codecs the connected device can use, with their capability bitmasks. */
    fun getSelectableCapabilities(a2dp: BluetoothA2dp?, device: BluetoothDevice?): List<CodecCapability> {
        val status = getCodecStatus(a2dp, device) ?: return cachedCapabilities
        val caps = parseSelectable(status)
        if (caps.isNotEmpty()) cachedCapabilities = caps
        return caps.ifEmpty { cachedCapabilities }
    }

    /**
     * Parse a BluetoothCodecStatus delivered by the CODEC_CONFIG_CHANGED broadcast and
     * refresh the shared cache. Accepts Any? so callers don't need the system type.
     */
    fun parseStatusObject(status: Any?): AudioInfo? {
        if (status == null) return null
        val config = invokeNoArg(status, "getCodecConfig")
        val info = config?.let { parseConfig(it) }
        if (info != null) cachedAudioInfo = info
        val caps = parseSelectable(status)
        if (caps.isNotEmpty()) cachedCapabilities = caps
        Log.d(TAG, "parseStatusObject -> info=$info, caps=${caps.size}")
        return info
    }

    private fun parseSelectable(status: Any): List<CodecCapability> {
        val list = invokeNoArg(status, "getCodecsSelectableCapabilities") as? List<*> ?: return emptyList()
        val result = mutableListOf<CodecCapability>()
        for (cfg in list) {
            if (cfg == null) continue
            val info = parseConfig(cfg) ?: continue
            result.add(
                CodecCapability(
                    codecType = info.codecType,
                    codecName = info.codecName,
                    sampleRateMask = info.sampleRateMask,
                    bitsPerSampleMask = info.bitsPerSampleMask,
                    channelModeMask = info.channelModeMask,
                    codecSpecific1 = info.codecSpecific1
                )
            )
        }
        return result
    }

    /**
     * Parse a BluetoothCodecConfig. Prefers public getter methods, falling back to
     * parsing toString() (which is never blocked by hidden-API restrictions).
     */
    private fun parseConfig(config: Any): AudioInfo? {
        val text = config.toString()

        val codecType = readInt(config, "getCodecType")
            ?: extractInt(text, "codecType")
            ?: extractInt(text, "mCodecType")
            ?: return null

        val codecName = extractString(text, "codecName")
            ?: extractString(text, "mCodecName")
            ?: defaultCodecName(codecType)

        val sampleRate = readInt(config, "getSampleRate")
            ?: extractMask(text, "sampleRate")
            ?: extractMask(text, "mSampleRate")
            ?: 0
        val bits = readInt(config, "getBitsPerSample")
            ?: extractMask(text, "bitsPerSample")
            ?: extractMask(text, "mBitsPerSample")
            ?: 0
        val channel = readInt(config, "getChannelMode")
            ?: extractMask(text, "channelMode")
            ?: extractMask(text, "mChannelMode")
            ?: 0
        val cs1 = readLong(config, "getCodecSpecific1")
            ?: extractLong(text, "codecSpecific1")
            ?: extractLong(text, "mCodecSpecific1")
            ?: 0L

        return AudioInfo(codecType, normalizeCodecName(codecName), sampleRate, bits, channel, cs1)
    }

    // =====================================================================
    // Writing
    // =====================================================================

    /**
     * Apply a codec change. sampleRate / bitsPerSample / channelMode are single bitmask
     * values (use 0 to inherit from the current configuration).
     */
    @SuppressLint("MissingPermission")
    fun setCodec(
        a2dp: BluetoothA2dp?,
        device: BluetoothDevice?,
        codecType: Int,
        sampleRate: Int,
        bitsPerSample: Int,
        channelMode: Int,
        codecSpecific1: Long,
        onResult: ((Boolean, String) -> Unit)? = null
    ) {
        if (a2dp == null || device == null) {
            onResult?.invoke(false, "No A2DP device connected")
            return
        }

        val target = buildConfig(codecType, sampleRate, bitsPerSample, channelMode, codecSpecific1)
        if (target == null) {
            onResult?.invoke(false, "Unable to build codec config on this device")
            return
        }

        try {
            if (codecSpecific1 != 0L) {
                // Two-step: apply with cs1=0 first, then the real value.
                val step1 = buildConfig(codecType, sampleRate, bitsPerSample, channelMode, 0L)
                if (step1 != null) invokeSetCodec(a2dp, device, step1)
                handler.postDelayed({
                    try {
                        invokeSetCodec(a2dp, device, target)
                        onResult?.invoke(true, "Applied")
                    } catch (e: Exception) {
                        reportFailure(e, onResult)
                    }
                }, 300)
            } else {
                invokeSetCodec(a2dp, device, target)
                onResult?.invoke(true, "Applied")
            }
        } catch (e: Exception) {
            reportFailure(e, onResult)
        }
    }

    @SuppressLint("MissingPermission")
    private fun invokeSetCodec(a2dp: BluetoothA2dp, device: BluetoothDevice, config: Any) {
        val m = a2dp.javaClass.getMethod(
            "setCodecConfigPreference",
            BluetoothDevice::class.java,
            BluetoothCodecConfig::class.java
        )
        m.invoke(a2dp, device, config)
        Log.d(TAG, "setCodecConfigPreference invoked with $config")
    }

    private fun reportFailure(e: Exception, onResult: ((Boolean, String) -> Unit)?) {
        val cause = (e as? InvocationTargetException)?.cause ?: e
        val privileged = cause.message?.contains("BLUETOOTH_PRIVILEGED", ignoreCase = true) == true
        Log.e(TAG, "Codec change failed: ${cause.javaClass.simpleName}: ${cause.message}", e)
        val msg = when {
            privileged -> "Android blocked codec change (privileged permission required)"
            cause is SecurityException -> "Permission denied by Android"
            else -> "Codec change failed: ${cause.message}"
        }
        onResult?.invoke(false, msg)
    }

    /** Build a BluetoothCodecConfig via the 9-arg legacy constructor, falling back to Builder. */
    private fun buildConfig(
        codecType: Int,
        sampleRate: Int,
        bitsPerSample: Int,
        channelMode: Int,
        codecSpecific1: Long
    ): Any? {
        // Legacy 9-arg constructor (works on most devices, matches reference app)
        try {
            val ctor = BluetoothCodecConfig::class.java.getDeclaredConstructor(
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Long::class.javaPrimitiveType,
                Long::class.javaPrimitiveType,
                Long::class.javaPrimitiveType,
                Long::class.javaPrimitiveType
            )
            ctor.isAccessible = true
            return ctor.newInstance(
                codecType, PRIORITY_HIGHEST, sampleRate, bitsPerSample, channelMode,
                codecSpecific1, 0L, 0L, 0L
            )
        } catch (e: Exception) {
            Log.w(TAG, "Legacy constructor failed (${e.message}), trying Builder")
        }

        // Builder fallback (newer API levels)
        return try {
            val builderClass = Class.forName("android.bluetooth.BluetoothCodecConfig\$Builder")
            val builder = builderClass.getConstructor().newInstance()
            builderClass.getMethod("setCodecType", Int::class.javaPrimitiveType).invoke(builder, codecType)
            builderClass.getMethod("setCodecPriority", Int::class.javaPrimitiveType).invoke(builder, PRIORITY_HIGHEST)
            builderClass.getMethod("setSampleRate", Int::class.javaPrimitiveType).invoke(builder, sampleRate)
            builderClass.getMethod("setBitsPerSample", Int::class.javaPrimitiveType).invoke(builder, bitsPerSample)
            builderClass.getMethod("setChannelMode", Int::class.javaPrimitiveType).invoke(builder, channelMode)
            builderClass.getMethod("setCodecSpecific1", Long::class.javaPrimitiveType).invoke(builder, codecSpecific1)
            builderClass.getMethod("build").invoke(builder)
        } catch (e: Exception) {
            Log.e(TAG, "Builder construction failed: ${e.message}")
            null
        }
    }

    // =====================================================================
    // Reflection helpers
    // =====================================================================

    private fun invokeNoArg(target: Any, method: String): Any? = try {
        target.javaClass.getMethod(method).invoke(target)
    } catch (e: Exception) {
        Log.w(TAG, "$method failed: ${e.message}")
        null
    }

    private fun readInt(target: Any, method: String): Int? = try {
        target.javaClass.getMethod(method).invoke(target) as? Int
    } catch (e: Throwable) {
        null
    }

    private fun readLong(target: Any, method: String): Long? = try {
        target.javaClass.getMethod(method).invoke(target) as? Long
    } catch (e: Throwable) {
        null
    }

    // ---- toString() parsing ----
    // Handles tokens like "codecName:LDAC", "mCodecType: 4", "mSampleRate: 0x4".

    private fun extractToken(text: String, key: String): String? {
        val regex = Regex("""\b$key\s*[:=]\s*([^,}\s]+)""", RegexOption.IGNORE_CASE)
        return regex.find(text)?.groupValues?.get(1)?.trim()
    }

    private fun extractString(text: String, key: String): String? =
        extractToken(text, key)?.takeIf { it.isNotBlank() && !it.equals("null", true) }

    private fun extractInt(text: String, key: String): Int? =
        parseNumber(extractToken(text, key))?.toInt()

    private fun extractMask(text: String, key: String): Int? =
        parseNumber(extractToken(text, key))?.toInt()

    private fun extractLong(text: String, key: String): Long? =
        parseNumber(extractToken(text, key))

    private fun parseNumber(raw: String?): Long? {
        val s = raw?.trim() ?: return null
        return try {
            if (s.startsWith("0x", true)) s.substring(2).toLong(16) else s.toLong()
        } catch (e: NumberFormatException) {
            null
        }
    }

    // =====================================================================
    // Labels / naming
    // =====================================================================

    fun defaultCodecName(type: Int): String = when (type) {
        TYPE_SBC -> "SBC"
        TYPE_AAC -> "AAC"
        TYPE_APTX -> "aptX"
        TYPE_APTX_HD -> "aptX HD"
        TYPE_LDAC -> "LDAC"
        TYPE_OPUS -> "Opus"
        else -> "Unknown"
    }

    fun normalizeCodecName(name: String): String = when {
        name.equals("APTX-HD", true) || name.equals("APTX HD", true) -> "aptX HD"
        name.equals("APTX-LL", true) || name.equals("APTX LL", true) -> "aptX LL"
        name.equals("APTX", true) -> "aptX"
        name.equals("LDAC", true) -> "LDAC"
        name.equals("OPUS", true) -> "Opus"
        name.equals("AAC", true) -> "AAC"
        name.equals("SBC", true) -> "SBC"
        else -> name
    }

    /** Decode a sample-rate bitmask into individual (bit, label) options, ascending. */
    fun sampleRateOptions(mask: Int): List<Pair<Int, String>> =
        listOf(SR_44100, SR_48000, SR_88200, SR_96000, SR_176400, SR_192000)
            .filter { mask and it != 0 }
            .map { it to sampleRateLabel(it) }

    /** Decode a bits-per-sample bitmask into individual (bit, label) options, ascending. */
    fun bitsOptions(mask: Int): List<Pair<Int, String>> =
        listOf(BPS_16, BPS_24, BPS_32)
            .filter { mask and it != 0 }
            .map { it to bitsLabel(it) }

    fun sampleRateLabel(mask: Int): String = when (mask) {
        SR_44100 -> "44.1 kHz"
        SR_48000 -> "48 kHz"
        SR_88200 -> "88.2 kHz"
        SR_96000 -> "96 kHz"
        SR_176400 -> "176.4 kHz"
        SR_192000 -> "192 kHz"
        0 -> "Auto"
        else -> "Unknown"
    }

    fun bitsLabel(mask: Int): String = when (mask) {
        BPS_16 -> "16-bit"
        BPS_24 -> "24-bit"
        BPS_32 -> "32-bit"
        0 -> "Auto"
        else -> "Unknown"
    }

    fun channelLabel(mask: Int): String = when (mask) {
        CH_MONO -> "Mono"
        CH_STEREO -> "Stereo"
        CH_MONO or CH_STEREO -> "Stereo"
        0 -> "Auto"
        else -> "Unknown"
    }

    fun playbackQuality(type: Int, sampleRateLabel: String): String = when {
        type == TYPE_LDAC && (sampleRateLabel.contains("96") || sampleRateLabel.contains("176") || sampleRateLabel.contains("192")) -> "Hi-Res"
        type == TYPE_LDAC -> "High"
        type == TYPE_APTX_HD -> "High"
        else -> "Standard"
    }
}
