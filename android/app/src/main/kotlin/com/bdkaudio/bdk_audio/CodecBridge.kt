package com.bdkaudio.bdk_audio

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.BluetoothDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Parcelable
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.InvocationTargetException
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicInteger

internal data class CodecConfigMap(
    val codecType: Int, val codecName: String, val sampleRateMask: Int,
    val bitsMask: Int, val channelMask: Int,
    val cs1: Long, val cs2: Long, val cs3: Long, val cs4: Long,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "codecType" to codecType, "codecName" to codecName,
        "sampleRateMask" to sampleRateMask, "bitsMask" to bitsMask,
        "channelMask" to channelMask, "cs1" to cs1, "cs2" to cs2,
        "cs3" to cs3, "cs4" to cs4,
    )
}

internal object CodecWire {
    fun requestedInt(value: Any?, field: String): Int {
        val number = requestedLong(value, field)
        require(number in 0..Int.MAX_VALUE.toLong()) { "Invalid integer $field" }
        return number.toInt()
    }
    fun requestedLong(value: Any?, field: String): Long = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> throw IllegalArgumentException("Missing signed integer $field")
    }
    private fun token(text: String, key: String): String? =
        Regex("\\b(?:m)?${Regex.escape(key)}\\s*[:=]\\s*([^,}\\s]+)", RegexOption.IGNORE_CASE)
            .find(text)?.groupValues?.get(1)?.substringBefore('(')

    private fun number(config: Any, method: String, text: String, key: String): Long? {
        try {
            val value = config.javaClass.getMethod(method).invoke(config)
            if (value is Int) return value.toLong()
            if (value is Long) return value
        } catch (_: Exception) { /* Source-provided toString data may still be available. */ }
        val raw = token(text, key) ?: return null
        return if (raw.startsWith("0x", true)) raw.substring(2).toULongOrNull(16)?.toLong()
        else raw.toLongOrNull()
    }

    fun parse(config: Any): CodecConfigMap? {
        val text = config.toString()
        fun int(method: String, key: String): Int? = number(config, method, text, key)
            ?.takeIf { it in 0..Int.MAX_VALUE.toLong() }?.toInt()
        val type = int("getCodecType", "codecType") ?: return null
        val rate = int("getSampleRate", "sampleRate") ?: return null
        val bits = int("getBitsPerSample", "bitsPerSample") ?: return null
        val channels = int("getChannelMode", "channelMode") ?: return null
        val specifics = (1..4).map { number(config, "getCodecSpecific$it", text, "codecSpecific$it") ?: return null }
        val name = Regex("\\b(?:m)?codecName\\s*[:=]\\s*([^,}]+)", RegexOption.IGNORE_CASE)
            .find(text)?.groupValues?.get(1)?.trim()?.takeUnless { it.equals("null", true) }
            ?: when (type) { 0 -> "SBC"; 1 -> "AAC"; 2 -> "aptX"; 3 -> "aptX HD"; 4 -> "LDAC"; 6 -> "Opus"; else -> "Codec $type" }
        return CodecConfigMap(type, name, rate, bits, channels, specifics[0], specifics[1], specifics[2], specifics[3])
    }

    fun selectDevice(devices: List<Pair<String, String>>, requested: String?): String? {
        if (requested != null) return devices.singleOrNull { it.first.equals(requested, true) }?.first
        val sole = devices.singleOrNull() ?: return null
        return sole.first.takeIf { Regex("^BDK(?:[\\s_-]|$)", RegexOption.IGNORE_CASE).containsMatchIn(sole.second.trim()) }
    }

    private val ldacCodes = listOf(1000L, 1001L, 1002L, 1003L)
    private val ldacRates = listOf(1, 2, 4, 8)
    fun ldacQualityCodes(active: CodecConfigMap, capabilities: List<CodecConfigMap>): List<Long> =
        if (active.codecType == 4 && (active.cs1 == 0L || active.cs1 in ldacCodes) && active.sampleRateMask in ldacRates &&
            capabilities.any { it.codecType == 4 &&
                it.sampleRateMask and active.sampleRateMask == active.sampleRateMask &&
                active.bitsMask > 0 && active.bitsMask and (active.bitsMask - 1) == 0 &&
                it.bitsMask and active.bitsMask == active.bitsMask &&
                active.channelMask > 0 && active.channelMask and (active.channelMask - 1) == 0 &&
                it.channelMask and active.channelMask == active.channelMask }) ldacCodes else emptyList()

    private fun recognizedLhdcV5(active: CodecConfigMap): Boolean {
        val name = active.codecName.uppercase(Locale.ROOT).replace(Regex("[\\s_-]"), "")
        val activeIndex = (active.cs1 and 0xffL).toInt()
        return active.codecType > 6 && name == "LHDCV5" &&
            active.cs1 and 0xc000L == 0x8000L && activeIndex in 0..9 &&
            active.cs3 and 0xff000000L == 0x5c000000L &&
            active.sampleRateMask in listOf(1, 2, 8, 32)
    }
    private fun lhdcV5QualityChange(requested: CodecConfigMap, capabilities: List<CodecConfigMap>, active: CodecConfigMap): Boolean {
        val index = (requested.cs1 and 0xffL).toInt()
        if (!recognizedLhdcV5(active) ||
            requested.codecType != active.codecType ||
            requested.sampleRateMask !in listOf(1, 2, 8, 32) || index !in 0..9 ||
            requested.cs1 and 0xffL.inv() != active.cs1 and 0xffL.inv()) return false
        if (!capabilities.any { it.codecType == active.codecType &&
                it.sampleRateMask and active.sampleRateMask == active.sampleRateMask &&
                active.bitsMask > 0 && active.bitsMask and (active.bitsMask - 1) == 0 &&
                it.bitsMask and active.bitsMask == active.bitsMask &&
                active.channelMask > 0 && active.channelMask and (active.channelMask - 1) == 0 &&
                it.channelMask and active.channelMask == active.channelMask }) return false
        if (index == 9) return true // ABR; no fixed measured bitrate.
        if (active.cs3 and 0x180L != 0L) return false // Lossless requires ABR.
        return if (requested.sampleRateMask in listOf(8, 32)) index >= 3 else index <= 7
    }

    fun validate(requested: CodecConfigMap, capabilities: List<CodecConfigMap>, active: CodecConfigMap) {
        fun single(value: Int) = value > 0 && value and (value - 1) == 0
        require(requested.codecType >= 0 && single(requested.sampleRateMask) && single(requested.bitsMask) && single(requested.channelMask)) {
            "Choose one explicit sample rate, bit depth and channel mode. Auto and multiple bits are not valid apply requests."
        }
        require(capabilities.any { it.codecType == requested.codecType &&
            it.sampleRateMask and requested.sampleRateMask == requested.sampleRateMask &&
            it.bitsMask and requested.bitsMask == requested.bitsMask &&
            it.channelMask and requested.channelMask == requested.channelMask }) {
            "The connected device's fresh selectable capabilities do not support this codec/rate/depth/channel combination."
        }
        val same = active.takeIf { it.codecType == requested.codecType }
        require(requested.cs2 == (same?.cs2 ?: 0L) && requested.cs3 == (same?.cs3 ?: 0L) &&
            requested.cs4 == (same?.cs4 ?: 0L)) { "Opaque vendor codec fields cannot be changed." }
        if (same != null && recognizedLhdcV5(active)) {
            require(lhdcV5QualityChange(requested, capabilities, active)) {
                "The requested LHDC V5 rate/quality/lossless tuple is not a recognized valid request."
            }
        } else if (requested.cs1 != (same?.cs1 ?: 0L)) {
            require((requested.codecType == 4 && requested.sampleRateMask in ldacRates &&
                requested.cs1 in ldacQualityCodes(active, capabilities)) ||
                lhdcV5QualityChange(requested, capabilities, active)) {
                "This connection does not expose that recognized LDAC or LHDC V5 quality request."
            }
        }
    }
}

internal data class ObservedCodecStatus(
    val active: CodecConfigMap, val capabilities: List<CodecConfigMap>,
    val observedAtMs: Long, val elapsedMs: Long,
)

internal class CodecStatusCache {
    private val values = mutableMapOf<String, Pair<Long, ObservedCodecStatus>>()
    private val submittedAfter = mutableMapOf<String, Long>()
    @Synchronized fun put(id: String, epoch: Long, value: ObservedCodecStatus) {
        val key = id.lowercase(Locale.ROOT)
        if (value.elapsedMs > (submittedAfter[key] ?: Long.MIN_VALUE)) values[key] = epoch to value
    }
    @Synchronized fun get(id: String, epoch: Long, nowElapsed: Long): ObservedCodecStatus? {
        val cached = values[id.lowercase(Locale.ROOT)] ?: return null
        val age = nowElapsed - cached.second.elapsedMs
        return cached.second.takeIf { cached.first == epoch && age in 0..5_000 }
    }
    @Synchronized fun remove(id: String) { values.remove(id.lowercase(Locale.ROOT)) }
    @Synchronized fun invalidateBefore(id: String, elapsed: Long) {
        val key = id.lowercase(Locale.ROOT)
        values.remove(key)
        submittedAfter[key] = maxOf(submittedAfter[key] ?: Long.MIN_VALUE, elapsed)
    }
    @Synchronized fun clear() { values.clear(); submittedAfter.clear() }
}

/** Normal app access only: no accessibility override, hidden-API exemption,
 * privileged permission request, pairing, A2DP connect or audio-route mutation. */
@Suppress("DEPRECATION")
class CodecBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    companion object {
        private val consentCodes = AtomicInteger(0x5d00)
        private val issuedConsentCodes = ConcurrentHashMap.newKeySet<Int>()
        private const val CODEC_ACTION = "android.bluetooth.a2dp.profile.action.CODEC_CONFIG_CHANGED"
        private const val CODEC_EXTRA = "android.bluetooth.extra.CODEC_STATUS"
        private const val NATIVE_TIMEOUT_MS = 8_000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "BDK-codec") }
    private val channel = MethodChannel(messenger, "bdk_audio/codec")
    private val closed = AtomicBoolean(false)
    private val applying = AtomicBoolean(false)
    private val nextRequest = AtomicLong()
    private val requests = ConcurrentHashMap<Long, NativeRequest>()
    private val cache = CodecStatusCache()
    private val epochs = ConcurrentHashMap<String, Long>()
    private val adapter = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    @Volatile private var a2dp: BluetoothA2dp? = null
    @Volatile private var profileFailure: String? = null
    @Volatile private var associationFailure: String? = null
    private var profileRequested = false
    private var receiverRegistered = false
    private var consent: Consent? = null

    private class NativeRequest(val result: MethodChannel.Result) {
        val live = AtomicBoolean(true)
        lateinit var timeout: Runnable
        fun check() { check(live.get()) { "Codec request was cancelled or timed out." } }
    }
    private class Consent(val result: MethodChannel.Result, val deviceId: String?, val permission: Boolean) {
        val requestCode = consentCodes.incrementAndGet().also { require(it <= 0xffff) { "Restart the app before requesting more Bluetooth consents." } }
        lateinit var timeout: Runnable
        var chooserLaunched = false
    }

    private val listener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile != BluetoothProfile.A2DP) return
            if (closed.get()) {
                try { adapter?.closeProfileProxy(profile, proxy) } catch (_: Exception) { }
                return
            }
            a2dp = proxy as? BluetoothA2dp
            profileRequested = false
            profileFailure = null
        }
        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.A2DP) {
                a2dp = null
                profileRequested = false
                cache.clear()
                epochs.replaceAll { _, epoch -> epoch + 1 }
            }
        }
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (closed.get() || intent == null) return
            if (intent.action == android.bluetooth.BluetoothAdapter.ACTION_STATE_CHANGED) {
                cache.clear()
                epochs.replaceAll { _, epoch -> epoch + 1 }
                return
            }
            val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE) ?: return
            val id = device.address.lowercase(Locale.ROOT)
            if (intent.action == BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED) {
                epochs.merge(id, 1L) { old, one -> old + one }
                cache.remove(id)
                return
            }
            if (intent.action != CODEC_ACTION) return
            val status = intent.getParcelableExtra<Parcelable>(CODEC_EXTRA) ?: return
            val epoch = epochs[id] ?: 0L
            val at = System.currentTimeMillis()
            val elapsed = SystemClock.elapsedRealtime()
            worker.execute {
                try {
                    if (!closed.get() && hasPermission() && epoch == (epochs[id] ?: 0L) &&
                        a2dp?.connectedDevices?.any { it.address.equals(id, true) } == true) {
                        parseStatus(status, at, elapsed)?.let { cache.put(id, epoch, it) }
                    }
                } catch (_: Exception) { /* A disconnect/permission loss invalidates the observation. */ }
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
        val filter = IntentFilter(CODEC_ACTION).apply {
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(android.bluetooth.BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        try {
            val senderPermission = if (Build.VERSION.SDK_INT >= 31) Manifest.permission.BLUETOOTH_CONNECT else Manifest.permission.BLUETOOTH
            if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(receiver, filter, senderPermission, handler, Context.RECEIVER_EXPORTED)
            else activity.registerReceiver(receiver, filter, senderPermission, handler)
            receiverRegistered = true
        } catch (error: Exception) { profileFailure = "Codec broadcast access is unavailable: ${rootCause(error).message}" }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed.get()) { result.error("codecClosed", "Codec activity is closed.", null); return }
        when (call.method) {
            "snapshot" -> dispatch(result) { snapshot(call.argument("deviceId"), it) }
            "requestPermission" -> requestPermission(result)
            "associate" -> associate(call.argument("deviceId"), result)
            "openBluetoothSettings" -> try {
                activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                result.success(mapOf("opened" to true))
            } catch (error: Exception) { result.error("settingsUnavailable", rootCause(error).message, null) }
            "apply" -> {
                if (!applying.compareAndSet(false, true)) {
                    result.error("codecBusy", "A codec request is already in progress. Wait for its readback or timeout.", null)
                } else dispatch(result, apply = true) { apply(call, it) }
            }
            else -> result.notImplemented()
        }
    }

    private fun dispatch(result: MethodChannel.Result, apply: Boolean = false, work: (NativeRequest) -> Any?) {
        val id = nextRequest.incrementAndGet()
        val request = NativeRequest(result)
        request.timeout = Runnable {
            if (request.live.compareAndSet(true, false)) {
                requests.remove(id)
                result.error("codecTimeout", if (apply) "Codec submission timed out. Its outcome is unknown; refresh actual device state before another change." else "Android Bluetooth did not respond. Check Bluetooth settings and retry.", null)
            }
        }
        requests[id] = request
        handler.postDelayed(request.timeout, NATIVE_TIMEOUT_MS)
        worker.execute {
            try {
                request.check()
                check(!closed.get()) { "Codec activity was closed." }
                val value = work(request)
                handler.post {
                    if (request.live.compareAndSet(true, false)) {
                        handler.removeCallbacks(request.timeout)
                        requests.remove(id)
                        result.success(value)
                    }
                }
            } catch (error: Exception) {
                val cause = rootCause(error)
                handler.post {
                    if (request.live.compareAndSet(true, false)) {
                        handler.removeCallbacks(request.timeout)
                        requests.remove(id)
                        result.error(if (cause is IllegalArgumentException) "invalidCodecRequest" else "codecUnavailable",
                            "${cause.javaClass.simpleName}: ${cause.message}. Android/OEM restrictions may prevent app codec control.", null)
                    }
                }
            } finally { if (apply) applying.set(false) }
        }
    }

    private fun hasPermission() = Build.VERSION.SDK_INT < 31 || activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun requestProxy() {
        if (closed.get() || profileRequested || a2dp != null || !hasPermission()) return
        profileRequested = true
        try {
            if (adapter?.getProfileProxy(activity, listener, BluetoothProfile.A2DP) != true) {
                profileRequested = false
                profileFailure = "Android A2DP profile service is unavailable. Check Bluetooth settings."
            } else handler.postDelayed({
                if (!closed.get() && a2dp == null && profileRequested) {
                    profileRequested = false
                    profileFailure = "Android A2DP profile service timed out. Reopen Audio quality or check Bluetooth settings."
                }
            }, NATIVE_TIMEOUT_MS)
        } catch (error: Exception) { profileRequested = false; profileFailure = rootCause(error).message }
    }

    private fun snapshot(requestedId: String?, request: NativeRequest): Map<String, Any?> = try {
        snapshotImpl(requestedId, request)
    } catch (error: Exception) {
        val cause = rootCause(error)
        mapOf("state" to (if (!hasPermission()) "permissionRequired" else "error"),
            "devices" to emptyList<Any>(), "selectedDeviceId" to null,
            "active" to null, "capabilities" to emptyList<Any>(), "canApply" to false,
            "source" to "none", "observedAtMs" to 0L,
            "reason" to "${cause.javaClass.simpleName}: ${cause.message}. Check Bluetooth access and refresh the connected audio devices.")
    }

    private fun snapshotImpl(requestedId: String?, request: NativeRequest): Map<String, Any?> {
        request.check()
        fun unavailable(state: String, reason: String, devices: List<Map<String, Any?>> = emptyList(), selected: String? = null) = mapOf<String, Any?>(
            "state" to state, "devices" to devices, "selectedDeviceId" to selected,
            "active" to null, "capabilities" to emptyList<Any>(), "canApply" to false,
            "source" to "none", "observedAtMs" to 0L, "reason" to reason,
        )
        if (!hasPermission()) return unavailable("permissionRequired", "Allow Nearby devices / Bluetooth permission to read connected audio devices.")
        if (adapter == null) return unavailable("apiUnavailable", "This Android device has no Bluetooth adapter.")
        if (!adapter.isEnabled) return unavailable("bluetoothOff", "Turn on Bluetooth and connect your speaker for audio.")
        val proxy = a2dp ?: run {
            handler.post { requestProxy() }
            return unavailable(if (profileFailure == null) "initializing" else "error", profileFailure ?: "Waiting for the Android A2DP profile service.")
        }
        val connected = proxy.connectedDevices.filter { proxy.getConnectionState(it) == BluetoothProfile.STATE_CONNECTED }
        val associations = associations()
        val devices = connected.map { mapOf<String, Any?>("id" to it.address, "name" to (it.name ?: "Bluetooth audio device"), "associated" to associations.contains(it.address.lowercase(Locale.ROOT))) }
        if (connected.isEmpty()) return unavailable("noAudioDevice", "Pair and connect the speaker for audio in Bluetooth settings. BLE discovery follows the audio connection.")
        val selectedId = CodecWire.selectDevice(connected.map { it.address to (it.name ?: "") }, requestedId)
            ?: return unavailable("noAudioDevice", if (requestedId != null) "The selected audio device is not currently connected." else "Select and confirm your speaker from the connected audio devices; the app will not choose unrelated headphones.", devices)
        val selected = connected.single { it.address == selectedId }
        if (Build.VERSION.SDK_INT < 26) return unavailable("apiUnavailable", "Codec/CDM app access requires Android 8 or later. Audio remains managed by Android.", devices, selectedId)
        if (associationFailure != null) return unavailable("apiUnavailable", "Companion Device access is unavailable: $associationFailure. Connected audio devices remain available for setup.", devices, selectedId)
        if (!associations.contains(selectedId.lowercase(Locale.ROOT))) return unavailable("associationRequired", "Allow the normal Companion Device association for this speaker to request codec access. Some Android/OEM versions still restrict these APIs.", devices, selectedId)
        val selectedEpoch = epochs[selectedId.lowercase(Locale.ROOT)] ?: 0L
        request.check()
        var source = "direct"
        var readFailure: String? = null
        val observation = try {
            val status = proxy.javaClass.getMethod("getCodecStatus", BluetoothDevice::class.java).invoke(proxy, selected)
            status?.let { parseStatus(it, System.currentTimeMillis(), SystemClock.elapsedRealtime()) }
        } catch (error: Exception) { readFailure = rootCause(error).let { "${it.javaClass.simpleName}: ${it.message}" }; null }
        val fresh = observation ?: cache.get(selectedId, selectedEpoch, SystemClock.elapsedRealtime()).also { source = "broadcast" }
            ?: return unavailable("apiUnavailable", "Android did not expose a current codec configuration${readFailure?.let { ": $it" } ?: "."} Association does not bypass hidden/System API restrictions.", devices, selectedId)
        request.check()
        if (proxy !== a2dp || proxy.getConnectionState(selected) != BluetoothProfile.STATE_CONNECTED ||
            selectedEpoch != (epochs[selectedId.lowercase(Locale.ROOT)] ?: 0L)) return unavailable("noAudioDevice", "The audio connection changed while reading codec status. Refresh the connected device list.", devices)
        val writable = try { setter(proxy); configFactoryAvailable() } catch (_: Exception) { false }
        return mapOf("state" to "ready", "devices" to devices, "selectedDeviceId" to selectedId,
            "active" to fresh.active.toMap(), "capabilities" to fresh.capabilities.map { it.toMap() },
            "canApply" to (writable && fresh.capabilities.isNotEmpty()), "source" to source,
            "observedAtMs" to fresh.observedAtMs,
            "reason" to when { !writable -> "Android/OEM does not expose an accessible codec setter/configuration factory. Current telemetry is read only."
                fresh.capabilities.isEmpty() -> "No selectable codec capabilities were exposed; changes are disabled."
                source == "broadcast" -> "Device-specific recent Android broadcast; each requested change still requires fresh negotiated readback."
                else -> "Android may refuse a preference. Only negotiated readback can confirm the result." })
    }

    private fun parseStatus(status: Any, at: Long, elapsed: Long): ObservedCodecStatus? {
        val active = status.javaClass.getMethod("getCodecConfig").invoke(status)?.let(CodecWire::parse) ?: return null
        val raw = try { status.javaClass.getMethod("getCodecsSelectableCapabilities").invoke(status) } catch (_: Exception) { null }
        val configurations = when (raw) { is List<*> -> raw; is Array<*> -> raw.toList(); else -> emptyList<Any>() }
        return ObservedCodecStatus(active, configurations.filterNotNull().mapNotNull(CodecWire::parse), at, elapsed)
    }

    private fun associations(): Set<String> {
        if (Build.VERSION.SDK_INT < 26) return emptySet()
        val cdm = activity.getSystemService(Context.COMPANION_DEVICE_SERVICE) as? CompanionDeviceManager ?: return emptySet()
        return try {
            val values = if (Build.VERSION.SDK_INT >= 33) cdm.myAssociations.mapNotNull { it.deviceMacAddress?.toString()?.lowercase(Locale.ROOT) }.toSet()
            else cdm.associations.map { it.lowercase(Locale.ROOT) }.toSet()
            associationFailure = null
            values
        } catch (error: Exception) {
            associationFailure = rootCause(error).let { "${it.javaClass.simpleName}: ${it.message}" }
            emptySet()
        }
    }

    private fun setter(proxy: BluetoothA2dp) = proxy.javaClass.getMethod("setCodecConfigPreference", BluetoothDevice::class.java, Class.forName("android.bluetooth.BluetoothCodecConfig"))
    private fun configFactoryAvailable(): Boolean = try { legacyConstructor(); true } catch (_: Exception) {
        try {
            val builder = Class.forName("android.bluetooth.BluetoothCodecConfig\$Builder")
            builder.getConstructor()
            for (name in listOf("CodecType", "CodecPriority", "SampleRate", "BitsPerSample", "ChannelMode")) builder.getMethod("set$name", Int::class.javaPrimitiveType)
            for (n in 1..4) builder.getMethod("setCodecSpecific$n", Long::class.javaPrimitiveType)
            builder.getMethod("build")
            true
        } catch (_: Exception) { false }
    }
    private fun legacyConstructor() = Class.forName("android.bluetooth.BluetoothCodecConfig").getConstructor(
        Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
        Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, Long::class.javaPrimitiveType,
        Long::class.javaPrimitiveType, Long::class.javaPrimitiveType, Long::class.javaPrimitiveType)

    private fun buildConfig(config: CodecConfigMap): Any {
        try { return legacyConstructor().newInstance(config.codecType, 1_000_000, config.sampleRateMask,
            config.bitsMask, config.channelMask, config.cs1, config.cs2, config.cs3, config.cs4) }
        catch (_: Exception) { /* Try the accessible builder, never suppress hidden API enforcement. */ }
        val type = Class.forName("android.bluetooth.BluetoothCodecConfig\$Builder")
        val builder = type.getConstructor().newInstance()
        for ((name, value) in listOf("CodecType" to config.codecType, "CodecPriority" to 1_000_000,
            "SampleRate" to config.sampleRateMask, "BitsPerSample" to config.bitsMask, "ChannelMode" to config.channelMask)) {
            type.getMethod("set$name", Int::class.javaPrimitiveType).invoke(builder, value)
        }
        for ((index, value) in listOf(config.cs1, config.cs2, config.cs3, config.cs4).withIndex()) {
            type.getMethod("setCodecSpecific${index + 1}", Long::class.javaPrimitiveType).invoke(builder, value)
        }
        return checkNotNull(type.getMethod("build").invoke(builder))
    }

    private fun apply(call: MethodCall, request: NativeRequest): Map<String, Boolean> {
        val id = requireNotNull(call.argument<String>("deviceId")) { "Select the exact connected audio device before applying." }
        val snapshot = snapshot(id, request)
        require(snapshot["state"] == "ready" && snapshot["canApply"] == true) { snapshot["reason"].toString() }
        val proxy = checkNotNull(a2dp) { "Android A2DP service disconnected." }
        val device = proxy.connectedDevices.singleOrNull { it.address.equals(id, true) }
            ?: throw IllegalArgumentException("Selected audio device is no longer connected.")
        fun int(key: String): Int = CodecWire.requestedInt(call.argument<Any>(key), key)
        fun long(key: String): Long = CodecWire.requestedLong(call.argument<Any>(key), key)
        val desired = CodecConfigMap(int("codecType"), "Requested", int("sampleRateMask"), int("bitsMask"), int("channelMask"), long("cs1"), long("cs2"), long("cs3"), long("cs4"))
        val epoch = epochs[id.lowercase(Locale.ROOT)] ?: 0L
        val status = try { proxy.javaClass.getMethod("getCodecStatus", BluetoothDevice::class.java).invoke(proxy, device) }
            catch (_: Exception) { null }
        val fresh = status?.let { parseStatus(it, System.currentTimeMillis(), SystemClock.elapsedRealtime()) }
            ?: cache.get(id, epoch, SystemClock.elapsedRealtime())
            ?: throw IllegalArgumentException("No fresh device-specific selectable capabilities are available.")
        CodecWire.validate(desired, fresh.capabilities, fresh.active)
        val config = buildConfig(desired)
        request.check()
        check(!closed.get() && hasPermission() && adapter?.isEnabled == true) { "Bluetooth access changed before submission." }
        check(associations().contains(id.lowercase(Locale.ROOT)) && proxy === a2dp &&
            proxy.getConnectionState(device) == BluetoothProfile.STATE_CONNECTED &&
            epoch == (epochs[id.lowercase(Locale.ROOT)] ?: 0L)) { "Audio device identity/connection/association changed before submission." }
        check(SystemClock.elapsedRealtime() - fresh.elapsedMs in 0..5_000) { "Selectable codec capabilities expired before submission. Refresh Audio quality." }
        request.check()
        cache.invalidateBefore(id, SystemClock.elapsedRealtime()) // Includes already-queued pre-request broadcasts.
        setter(proxy).invoke(proxy, device, config) // Exactly one invocation; no blind two-step change.
        return mapOf("submitted" to true)
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) { profileFailure = null; requestProxy(); dispatch(result) { snapshot(null, it) }; return }
        if (consent != null) { result.error("codecBusy", "A Bluetooth permission or companion consent is already open.", null); return }
        val pending = Consent(result, null, true)
        beginConsent(pending, 120_000)
        try { activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), pending.requestCode) }
        catch (error: Exception) { finishConsent(pending); result.error("permissionUnavailable", rootCause(error).message, null) }
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (!issuedConsentCodes.contains(requestCode)) return false
        val pending = consent?.takeIf { it.permission && it.requestCode == requestCode } ?: return true
        finishConsent(pending)
        profileFailure = null
        if (hasPermission()) requestProxy()
        dispatch(pending.result) { snapshot(null, it) }
        return true
    }

    private fun associate(id: String?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 26) { result.error("associationUnavailable", "Companion Device association requires Android 8 or later.", null); return }
        if (id == null || !android.bluetooth.BluetoothAdapter.checkBluetoothAddress(id.uppercase(Locale.ROOT))) { result.error("invalidDevice", "Select the exact connected speaker address before association.", null); return }
        if (!hasPermission()) { result.error("permissionRequired", "Allow Bluetooth permission first.", null); return }
        if (consent != null) { result.error("codecBusy", "A Bluetooth permission or companion consent is already open.", null); return }
        val cdm = activity.getSystemService(Context.COMPANION_DEVICE_SERVICE) as? CompanionDeviceManager
        if (cdm == null || !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)) { result.error("associationUnavailable", "This Android device does not expose Companion Device setup.", null); return }
        try {
            require(a2dp?.connectedDevices?.any { it.address.equals(id, true) } == true) { "The selected audio device is not connected. Pair it in Bluetooth settings first." }
            if (associations().contains(id.lowercase(Locale.ROOT))) { dispatch(result) { snapshot(id, it) }; return }
            val pending = Consent(result, id, false)
            beginConsent(pending, 180_000)
            val association = AssociationRequest.Builder().addDeviceFilter(BluetoothDeviceFilter.Builder().setAddress(id.uppercase(Locale.ROOT)).build()).setSingleDevice(true).build()
            val callback = if (Build.VERSION.SDK_INT >= 33) modernAssociationCallback(pending, id) else legacyAssociationCallback(pending)
            if (Build.VERSION.SDK_INT >= 33) cdm.associate(association, activity.mainExecutor, callback)
            else cdm.associate(association, callback, handler)
        } catch (error: Exception) {
            consent?.takeIf { it.result === result }?.let(::finishConsent)
            result.error("associationUnavailable", rootCause(error).message, null)
        }
    }

    private fun legacyAssociationCallback(pending: Consent) = object : CompanionDeviceManager.Callback() {
        @Deprecated("Legacy CDM callback used only below API33")
        override fun onDeviceFound(chooserLauncher: IntentSender) { launchConsent(pending, chooserLauncher) }
        override fun onFailure(error: CharSequence?) { associationFailed(pending, error) }
    }
    private fun modernAssociationCallback(pending: Consent, id: String) = object : CompanionDeviceManager.Callback() {
        override fun onAssociationPending(intentSender: IntentSender) { launchConsent(pending, intentSender) }
        override fun onAssociationCreated(associationInfo: AssociationInfo) {
            if (consent !== pending || closed.get()) return
            if (!associationInfo.deviceMacAddress?.toString().equals(id, true)) return
            completeAssociation(pending)
        }
        override fun onFailure(error: CharSequence?) { associationFailed(pending, error) }
    }
    private fun associationFailed(pending: Consent, error: CharSequence?) {
        if (consent !== pending || closed.get()) return
        finishConsent(pending)
        pending.result.error("associationFailed", error?.toString() ?: "Companion association was cancelled or refused.", null)
    }

    private fun beginConsent(pending: Consent, timeoutMs: Long) {
        consent = pending
        issuedConsentCodes.add(pending.requestCode)
        pending.timeout = Runnable {
            if (consent === pending) {
                finishConsent(pending)
                if (pending.chooserLaunched) try { activity.finishActivity(pending.requestCode) } catch (_: Exception) { }
                pending.result.error("consentTimeout", "Bluetooth consent timed out. Reopen it to try again.", null)
            }
        }
        handler.postDelayed(pending.timeout, timeoutMs)
    }
    private fun finishConsent(pending: Consent) {
        if (consent === pending) consent = null
        handler.removeCallbacks(pending.timeout)
    }
    private fun launchConsent(pending: Consent, launcher: IntentSender) {
        if (closed.get() || consent !== pending || pending.chooserLaunched) return
        pending.chooserLaunched = true
        try { activity.startIntentSenderForResult(launcher, pending.requestCode, null, 0, 0, 0) }
        catch (error: Exception) { finishConsent(pending); pending.result.error("associationUnavailable", rootCause(error).message, null) }
    }
    private fun completeAssociation(pending: Consent) {
        finishConsent(pending)
        cache.remove(pending.deviceId!!)
        dispatch(pending.result) { snapshot(pending.deviceId, it) }
    }
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (!issuedConsentCodes.contains(requestCode)) return false
        val pending = consent?.takeIf { !it.permission && it.requestCode == requestCode } ?: return true
        if (resultCode != Activity.RESULT_OK) {
            finishConsent(pending)
            pending.result.error("associationCancelled", "Companion Device association was cancelled.", null)
        } else if (Build.VERSION.SDK_INT < 33) completeAssociation(pending)
        // API33+ onAssociationCreated supplies the verified identity; keep the
        // finite deadline until that callback, not merely RESULT_OK.
        return true
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        consent?.let { pending ->
            finishConsent(pending)
            if (pending.chooserLaunched) try { activity.finishActivity(pending.requestCode) } catch (_: Exception) { }
            pending.result.error("codecClosed", "Codec activity closed during consent.", null)
        }
        for (request in requests.values) {
            handler.removeCallbacks(request.timeout)
            if (request.live.compareAndSet(true, false)) request.result.error("codecClosed", "Codec activity closed during request.", null)
        }
        requests.clear()
        if (receiverRegistered) {
            try { activity.unregisterReceiver(receiver) } catch (_: Exception) { }
            receiverRegistered = false
        }
        a2dp?.let { try { adapter?.closeProfileProxy(BluetoothProfile.A2DP, it) } catch (_: Exception) { } }
        a2dp = null
        cache.clear()
        worker.shutdownNow()
    }

    private fun rootCause(error: Throwable): Throwable = if (error is InvocationTargetException) error.targetException ?: error else error
}
