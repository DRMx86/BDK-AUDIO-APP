package com.example.myspeaker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothCodecStatus
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
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

/**
 * Dedicated full-screen codec control page.
 *
 * Lets the user pick a Bluetooth codec and, per codec, the Sample Rate and Bits Per Sample
 * supported by the connected device. Self-contained: obtains its own A2DP proxy and reads
 * codec info via [CodecManager].
 */
class CodecSettingsActivity : AppCompatActivity() {

    private val handler = Handler(Looper.getMainLooper())

    private var bluetoothA2dp: BluetoothA2dp? = null
    private var a2dpDevice: BluetoothDevice? = null
    private var expectedAddress: String? = null

    // Views
    private lateinit var tvCurrentCodecBig: TextView
    private lateinit var tvCurrentDetails: TextView
    private lateinit var tvDeviceLine: TextView
    private lateinit var tvStatusMessage: TextView
    private lateinit var codecContainer: LinearLayout
    private lateinit var sampleRateContainer: LinearLayout
    private lateinit var bitsContainer: LinearLayout
    private lateinit var lblSampleRate: TextView
    private lateinit var lblBits: TextView
    private lateinit var btnApply: Button

    // Companion Device Manager - required to READ codec status on some OEMs (e.g. Samsung).
    private var companionDeviceManager: CompanionDeviceManager? = null
    private var cdmRequested = false
    private var cdmAutoAttempted = false

    // Live polling (broadcast isn't delivered on some OEMs). Only refresh the UI when the
    // active codec actually changes, so we don't fight the user's in-progress selection.
    private var lastSignature: String? = null
    private val pollRunnable = object : Runnable {
        override fun run() {
            pollTick()
            handler.postDelayed(this, 2500)
        }
    }

    @SuppressLint("MissingPermission")
    private fun pollTick() {
        val info = CodecManager.getCurrentAudioInfo(bluetoothA2dp, resolveDevice())
        val sig = info?.let { "${it.codecType}/${it.sampleRateMask}/${it.bitsPerSampleMask}/${it.channelModeMask}" } ?: "none"
        if (sig != lastSignature) {
            lastSignature = sig
            refreshFromSystem()
        }
    }

    // State
    private var capabilities: List<CodecManager.CodecCapability> = emptyList()
    private var current: CodecManager.AudioInfo? = null
    private var selectedCodecType: Int = -1
    private var selectedSampleRate: Int = 0
    private var selectedBits: Int = 0

    private val codecViews = LinkedHashMap<Int, View>()
    private val sampleRateViews = LinkedHashMap<Int, View>()
    private val bitsViews = LinkedHashMap<Int, View>()

    // Fallback codec list when capabilities can't be read
    private val fallbackCodecs = listOf(
        CodecManager.TYPE_SBC,
        CodecManager.TYPE_AAC,
        CodecManager.TYPE_APTX,
        CodecManager.TYPE_APTX_HD,
        CodecManager.TYPE_LDAC
    )

    private val codecConfigReceiver = object : BroadcastReceiver() {
        @Suppress("DEPRECATION")
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_CODEC_CONFIG_CHANGED) return
            // The broadcast carries the full BluetoothCodecStatus (current config +
            // selectable capabilities). This is the reliable source on devices where
            // polling getCodecStatus() returns null.
            val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(
                    BluetoothCodecStatus.EXTRA_CODEC_STATUS,
                    BluetoothCodecStatus::class.java
                )
            } else {
                intent.getParcelableExtra<BluetoothCodecStatus>(BluetoothCodecStatus.EXTRA_CODEC_STATUS)
            }
            CodecManager.parseStatusObject(status)
            handler.postDelayed({ refreshFromSystem() }, 100)
        }
    }

    private val cdmAssociationLauncher = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        cdmRequested = false
        if (result.resultCode == RESULT_OK) {
            Toast.makeText(this, "Codec reading enabled", Toast.LENGTH_SHORT).show()
            handler.postDelayed({ refreshFromSystem() }, 300)
        } else {
            Toast.makeText(this, "Permission not granted", Toast.LENGTH_SHORT).show()
        }
    }

    private val a2dpListener = object : BluetoothProfile.ServiceListener {
        @SuppressLint("MissingPermission")
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
            if (profile == BluetoothProfile.A2DP) {
                bluetoothA2dp = proxy as? BluetoothA2dp
                refreshFromSystem()
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.A2DP) {
                bluetoothA2dp = null
                a2dpDevice = null
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_codec_settings)

        expectedAddress = intent.getStringExtra("device_address")
        companionDeviceManager = getSystemService(Context.COMPANION_DEVICE_SERVICE) as? CompanionDeviceManager

        bindViews()

        findViewById<ImageButton>(R.id.btnBack)?.setOnClickListener { finish() }
        btnApply.setOnClickListener { applyCodec() }

        registerCodecReceiver()
        connectA2dpProxy()

        // Show last-known data immediately (proxy connection is async).
        refreshFromSystem()
    }

    private fun bindViews() {
        tvCurrentCodecBig = findViewById(R.id.tvCurrentCodecBig)
        tvCurrentDetails = findViewById(R.id.tvCurrentDetails)
        tvDeviceLine = findViewById(R.id.tvDeviceLine)
        tvStatusMessage = findViewById(R.id.tvStatusMessage)
        codecContainer = findViewById(R.id.codecContainer)
        sampleRateContainer = findViewById(R.id.sampleRateContainer)
        bitsContainer = findViewById(R.id.bitsContainer)
        lblSampleRate = findViewById(R.id.lblSampleRate)
        lblBits = findViewById(R.id.lblBits)
        btnApply = findViewById(R.id.btnApplyCodec)
    }

    override fun onResume() {
        super.onResume()
        handler.postDelayed(pollRunnable, 800)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(pollRunnable)
    }

    @SuppressLint("MissingPermission")
    private fun hasCdmAssociationFor(device: BluetoothDevice): Boolean {
        val cdm = companionDeviceManager ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                cdm.myAssociations.any {
                    it.deviceMacAddress?.toString()?.equals(device.address, ignoreCase = true) == true
                }
            } else {
                @Suppress("DEPRECATION")
                cdm.associations.any { it.equals(device.address, ignoreCase = true) }
            }
        } catch (e: Exception) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestCdmAssociation(device: BluetoothDevice) {
        val cdm = companionDeviceManager
        if (cdm == null) {
            Toast.makeText(this, "Companion Device Manager unavailable", Toast.LENGTH_SHORT).show()
            return
        }
        if (hasCdmAssociationFor(device)) {
            handler.postDelayed({ refreshFromSystem() }, 100)
            return
        }
        if (cdmRequested) return
        cdmRequested = true

        val deviceFilter = BluetoothDeviceFilter.Builder()
            .setAddress(device.address)
            .build()
        val request = AssociationRequest.Builder()
            .addDeviceFilter(deviceFilter)
            .setSingleDevice(true)
            .build()

        cdm.associate(request, object : CompanionDeviceManager.Callback() {
            @Deprecated("Deprecated in API 33")
            override fun onDeviceFound(chooserLauncher: IntentSender) {
                try {
                    cdmAssociationLauncher.launch(IntentSenderRequest.Builder(chooserLauncher).build())
                } catch (e: Exception) {
                    cdmRequested = false
                }
            }

            override fun onAssociationCreated(associationInfo: AssociationInfo) {
                cdmRequested = false
                runOnUiThread { handler.postDelayed({ refreshFromSystem() }, 300) }
            }

            override fun onFailure(error: CharSequence?) {
                cdmRequested = false
            }
        }, handler)
    }

    private fun connectA2dpProxy() {
        try {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val ok = manager.adapter?.getProfileProxy(this, a2dpListener, BluetoothProfile.A2DP) ?: false
            if (!ok) showStatus("Bluetooth A2DP not available")
        } catch (e: Exception) {
            showStatus("Failed to access Bluetooth: ${e.message}")
        }
    }

    private fun registerCodecReceiver() {
        val filter = IntentFilter(ACTION_CODEC_CONFIG_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(codecConfigReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(codecConfigReceiver, filter)
        }
    }

    @SuppressLint("MissingPermission")
    private fun resolveDevice(): BluetoothDevice? {
        val connected = try {
            bluetoothA2dp?.connectedDevices
        } catch (e: SecurityException) {
            null
        } ?: return null
        if (connected.isEmpty()) return null
        val byAddress = expectedAddress?.let { addr ->
            connected.firstOrNull { it.address.equals(addr, ignoreCase = true) }
        }
        return byAddress ?: connected.singleOrNull() ?: connected.first()
    }

    @SuppressLint("MissingPermission")
    private fun refreshFromSystem() {
        val a2dp = bluetoothA2dp
        val device = resolveDevice()
        a2dpDevice = device

        // getCurrentAudioInfo / getSelectableCapabilities fall back to the cached
        // broadcast values when live polling returns null (e.g. on Samsung).
        current = CodecManager.getCurrentAudioInfo(a2dp, device)
        capabilities = CodecManager.getSelectableCapabilities(a2dp, device)

        tvDeviceLine.text = if (device != null) "Device: ${safeName(device)}" else "No audio device connected"

        val info = current
        val associated = device != null && hasCdmAssociationFor(device)
        if (info != null) {
            hideStatus()
            tvCurrentCodecBig.text = info.codecName
            tvCurrentDetails.text = "${info.sampleRateLabel} · ${info.bitsPerSampleLabel} · ${info.channelModeLabel}"
            // Default the selection to the active configuration.
            if (selectedCodecType == -1) {
                selectedCodecType = info.codecType
                selectedSampleRate = info.sampleRateMask
                selectedBits = info.bitsPerSampleMask
            }
            if (device == null) {
                showStatus("Showing last-known codec. Connect/play audio on the device to apply changes.")
            }
        } else {
            tvCurrentCodecBig.text = "Unknown"
            if (device != null && !associated) {
                // Reading codec status requires a Companion Device association on this OEM.
                // Auto-launch the system association dialog once (also requested on BLE connect).
                if (!cdmAutoAttempted && !cdmRequested) {
                    cdmAutoAttempted = true
                    requestCdmAssociation(device)
                }
                tvCurrentDetails.text = "Waiting for codec read permission for this device."
                showStatus("Allow access in the system dialog so the app can read the codec. (Changing the codec already works.)")
            } else {
                tvCurrentDetails.text = "Play audio on your Bluetooth device so Android reports the codec."
                showStatus("Couldn't read codec yet. Start playback on your Bluetooth speaker/headphones, then it will appear here.")
            }
        }

        buildCodecList()
    }

    // =====================================================================
    // Codec list
    // =====================================================================

    private fun buildCodecList() {
        codecContainer.removeAllViews()
        codecViews.clear()

        val types: List<Int> = if (capabilities.isNotEmpty()) {
            capabilities.map { it.codecType }.distinct()
        } else {
            fallbackCodecs
        }

        if (selectedCodecType == -1 && types.isNotEmpty()) {
            selectedCodecType = current?.codecType?.takeIf { types.contains(it) } ?: types.first()
        }

        for (type in types) {
            val name = capabilities.firstOrNull { it.codecType == type }?.codecName
                ?: CodecManager.defaultCodecName(type)
            val isActive = current?.codecType == type
            val subtitle = if (isActive) "Currently active" else null
            val row = makeOptionRow(name, subtitle) {
                selectedCodecType = type
                // Reset rate/bits to current device values for this codec when possible.
                onCodecSelected(type)
                updateCodecSelectionUi()
            }
            codecViews[type] = row
            codecContainer.addView(row)
        }

        updateCodecSelectionUi()
        onCodecSelected(selectedCodecType)
    }

    private fun updateCodecSelectionUi() {
        for ((type, view) in codecViews) {
            setRowSelected(view, type == selectedCodecType)
        }
    }

    /** Populate sample-rate and bits options for the selected codec. */
    private fun onCodecSelected(type: Int) {
        val cap = capabilities.firstOrNull { it.codecType == type }

        val rateOptions: List<Pair<Int, String>>
        val bitOptions: List<Pair<Int, String>>
        if (cap != null && (cap.sampleRateMask != 0 || cap.bitsPerSampleMask != 0)) {
            rateOptions = CodecManager.sampleRateOptions(cap.sampleRateMask)
            bitOptions = CodecManager.bitsOptions(cap.bitsPerSampleMask)
        } else {
            // Sensible defaults when device capabilities are unknown.
            rateOptions = listOf(
                CodecManager.SR_44100 to CodecManager.sampleRateLabel(CodecManager.SR_44100),
                CodecManager.SR_48000 to CodecManager.sampleRateLabel(CodecManager.SR_48000)
            )
            bitOptions = listOf(
                CodecManager.BPS_16 to CodecManager.bitsLabel(CodecManager.BPS_16),
                CodecManager.BPS_24 to CodecManager.bitsLabel(CodecManager.BPS_24)
            )
        }

        // Ensure a valid selection for this codec.
        if (rateOptions.none { it.first == selectedSampleRate }) {
            selectedSampleRate = if (current?.codecType == type &&
                rateOptions.any { it.first == current?.sampleRateMask }
            ) current!!.sampleRateMask else rateOptions.firstOrNull()?.first ?: 0
        }
        if (bitOptions.none { it.first == selectedBits }) {
            selectedBits = if (current?.codecType == type &&
                bitOptions.any { it.first == current?.bitsPerSampleMask }
            ) current!!.bitsPerSampleMask else bitOptions.firstOrNull()?.first ?: 0
        }

        buildOptionRows(sampleRateContainer, sampleRateViews, rateOptions, isSampleRate = true)
        buildOptionRows(bitsContainer, bitsViews, bitOptions, isSampleRate = false)

        val hasOptions = rateOptions.isNotEmpty() || bitOptions.isNotEmpty()
        lblSampleRate.visibility = if (rateOptions.isNotEmpty()) View.VISIBLE else View.GONE
        sampleRateContainer.visibility = if (rateOptions.isNotEmpty()) View.VISIBLE else View.GONE
        lblBits.visibility = if (bitOptions.isNotEmpty()) View.VISIBLE else View.GONE
        bitsContainer.visibility = if (bitOptions.isNotEmpty()) View.VISIBLE else View.GONE
        if (!hasOptions) {
            // nothing
        }
    }

    private fun buildOptionRows(
        container: LinearLayout,
        viewMap: LinkedHashMap<Int, View>,
        options: List<Pair<Int, String>>,
        isSampleRate: Boolean
    ) {
        container.removeAllViews()
        viewMap.clear()
        for ((bit, label) in options) {
            val row = makeOptionRow(label, null) {
                if (isSampleRate) selectedSampleRate = bit else selectedBits = bit
                updateOptionSelectionUi(viewMap, if (isSampleRate) selectedSampleRate else selectedBits)
            }
            viewMap[bit] = row
            container.addView(row)
        }
        updateOptionSelectionUi(viewMap, if (isSampleRate) selectedSampleRate else selectedBits)
    }

    private fun updateOptionSelectionUi(viewMap: LinkedHashMap<Int, View>, selectedBit: Int) {
        for ((bit, view) in viewMap) {
            setRowSelected(view, bit == selectedBit)
        }
    }

    // =====================================================================
    // Apply
    // =====================================================================

    @SuppressLint("MissingPermission")
    private fun applyCodec() {
        val a2dp = bluetoothA2dp
        val device = resolveDevice()
        if (a2dp == null || device == null) {
            Toast.makeText(this, "No Bluetooth audio device connected", Toast.LENGTH_SHORT).show()
            return
        }
        if (selectedCodecType == -1) {
            Toast.makeText(this, "Select a codec first", Toast.LENGTH_SHORT).show()
            return
        }

        // Preserve current channel mode (single value) where possible, else inherit.
        val channelMode = current?.channelModeMask?.takeIf { it == CodecManager.CH_STEREO || it == CodecManager.CH_MONO }
            ?: CodecManager.CH_STEREO

        btnApply.isEnabled = false
        showStatus("Applying ${CodecManager.defaultCodecName(selectedCodecType)}…", warn = false)

        CodecManager.setCodec(
            a2dp = a2dp,
            device = device,
            codecType = selectedCodecType,
            sampleRate = selectedSampleRate,
            bitsPerSample = selectedBits,
            channelMode = channelMode,
            codecSpecific1 = 0L
        ) { success, message ->
            runOnUiThread {
                btnApply.isEnabled = true
                if (success) {
                    Toast.makeText(this, "Codec applied", Toast.LENGTH_SHORT).show()
                    // Persist for the badge in the main screen.
                    getSharedPreferences("BDKAudioPrefs", MODE_PRIVATE).edit()
                        .putString("current_codec", CodecManager.defaultCodecName(selectedCodecType))
                        .apply()
                    handler.postDelayed({ verifyAndRefresh() }, 700)
                } else {
                    showStatus(message, warn = true)
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun verifyAndRefresh() {
        val info = CodecManager.getCurrentAudioInfo(bluetoothA2dp, resolveDevice())
        if (info != null && info.codecType != selectedCodecType) {
            showStatus(
                "Android kept ${info.codecName}. The codec may be disabled in Developer options " +
                    "or unsupported while audio is idle. Start playback and try again.",
                warn = true
            )
        }
        refreshFromSystem()
    }

    // =====================================================================
    // Row helpers
    // =====================================================================

    private fun makeOptionRow(title: String, subtitle: String?, onClick: () -> Unit): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = ContextCompat.getDrawable(this@CodecSettingsActivity, R.drawable.bdk_codec_option)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            lp.bottomMargin = dp(8)
            layoutParams = lp
            isClickable = true
            setOnClickListener { onClick() }
        }

        val textCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val titleView = TextView(this).apply {
            text = title
            textSize = 15f
            setTextColor(ContextCompat.getColor(this@CodecSettingsActivity, R.color.bdk_text_primary))
        }
        textCol.addView(titleView)
        if (!subtitle.isNullOrBlank()) {
            val sub = TextView(this).apply {
                text = subtitle
                textSize = 12f
                setTextColor(ContextCompat.getColor(this@CodecSettingsActivity, R.color.bdk_accent_primary))
            }
            textCol.addView(sub)
        }
        row.addView(textCol)

        val check = TextView(this).apply {
            text = "✓"
            textSize = 18f
            setTextColor(ContextCompat.getColor(this@CodecSettingsActivity, R.color.bdk_accent_primary))
            visibility = View.INVISIBLE
            tag = TAG_CHECK
        }
        row.addView(check)

        return row
    }

    private fun setRowSelected(row: View, selected: Boolean) {
        row.isSelected = selected
        row.isActivated = selected
        (row as? ViewGroup)?.findViewWithTag<TextView>(TAG_CHECK)?.visibility =
            if (selected) View.VISIBLE else View.INVISIBLE
    }

    @SuppressLint("MissingPermission")
    private fun safeName(device: BluetoothDevice): String = try {
        device.name ?: device.address
    } catch (e: SecurityException) {
        device.address
    }

    private fun showStatus(message: String, warn: Boolean = true) {
        tvStatusMessage.visibility = View.VISIBLE
        tvStatusMessage.text = message
        tvStatusMessage.setTextColor(
            ContextCompat.getColor(this, if (warn) R.color.bdk_warning else R.color.bdk_text_secondary)
        )
    }

    private fun hideStatus() {
        tvStatusMessage.visibility = View.GONE
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(codecConfigReceiver)
        } catch (_: Exception) {
        }
        try {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothA2dp?.let { manager?.adapter?.closeProfileProxy(BluetoothProfile.A2DP, it) }
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val ACTION_CODEC_CONFIG_CHANGED =
            "android.bluetooth.a2dp.profile.action.CODEC_CONFIG_CHANGED"
        private const val TAG_CHECK = "row_check"
    }
}
