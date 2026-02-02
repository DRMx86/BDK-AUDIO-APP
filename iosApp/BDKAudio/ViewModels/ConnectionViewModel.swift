import Foundation
import CoreBluetooth
import SwiftUI
import Combine
import sharedKit

/// Main view model handling BLE connection and device state
class ConnectionViewModel: ObservableObject {
    // Connection state
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var discoveredDevices: [BluetoothDevice] = []
    
    // Device info
    @Published var deviceName = "BDK Audio"
    @Published var firmwareVersion = "1.0.0"
    @Published var codecName = ""
    
    // EQ state
    @Published var selectedPresetId: Int32 = 0
    @Published var bass: Double = 12      // 0-24 range, 12 = 0 dB (like Android)
    @Published var mid: Double = 12       // 0-24 range, 12 = 0 dB
    @Published var treble: Double = 12    // 0-24 range, 12 = 0 dB
    
    // Level meter data (3 bands: 30Hz, 60Hz, 100Hz)
    @Published var meterLevel1: Double = 0  // 30Hz
    @Published var meterLevel2: Double = 0  // 60Hz
    @Published var meterLevel3: Double = 0  // 100Hz
    
    // LED state
    @Published var selectedEffect: LedEffect = LedEffect.companion.fromId(id: 0) // Spectrum Bars
    @Published var brightness: Double = 80
    @Published var speed: Double = 50
    @Published var primaryColor: Color = .cyan
    @Published var secondaryColor: Color = .purple
    @Published var gradientType: GradientType = GradientType.companion.fromId(id: 0) // None
    
    // Saved brightness for restore after "Off"
    var savedBrightness: Double = 80
    
    // Control toggles
    @Published var bassBoost = false
    @Published var bypassDsp = false
    @Published var channelFlip = false
    
    // Sound state (matching Android)
    @Published var soundStatus: Int = 0  // Bitmask: bit 0=startup, 1=pairing, 2=connected, 3=maxvol
    @Published var soundMuted = false
    
    // Audio info (from ESP32)
    @Published var sampleRate = ""
    @Published var bitsPerSample = ""
    @Published var channelMode = ""
    
    // OTA state
    @Published var currentMtu: Int = 23
    private var lastLedSendTime: Date = .distantPast
    
    // OTA flow control - semaphore signals when ready to send next packet
    private let otaWriteSemaphore = DispatchSemaphore(value: 0)
    private var otaInProgress = false
    
    // Rate limit sending: max 30 Hz (33ms between sends)
    private var eqSendTimer: Timer?
    private var pendingEqSend = false
    
    // LED rate limiting (same as EQ)
    private var ledSendTimer: Timer?
    private var pendingLedBrightnessSend = false
    private var pendingLedStateSend = false
    
    // Delayed LED state send work item (can be cancelled)
    private var delayedLedStateWorkItem: DispatchWorkItem?
    
    // Flag to prevent onChange triggering sendEq when we update from device
    private var isUpdatingFromDevice = false
    
    // Flag to prevent onChange triggering sendLed when we update from device
    private var isUpdatingLedFromDevice = false
    
    // BLE Manager
    private var bleDelegate: BLEDelegate!
    private var peripheral: CBPeripheral?
    private var cmdCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var meterCharacteristic: CBCharacteristic?
    
    // Store discovered peripherals for connection
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    
    // UUIDs from shared module
    private let serviceUUID = CBUUID(string: BleUnifiedProtocol.shared.SERVICE_UUID_STRING)
    private let cmdUUID = CBUUID(string: BleUnifiedProtocol.shared.CHAR_CMD_UUID_STRING)
    private let statusUUID = CBUUID(string: BleUnifiedProtocol.shared.CHAR_STATUS_UUID_STRING)
    private let meterUUID = CBUUID(string: BleUnifiedProtocol.shared.CHAR_METER_UUID_STRING)
    
    init() {
        bleDelegate = BLEDelegate(viewModel: self)
    }
    
    var centralManager: CBCentralManager {
        bleDelegate.centralManager
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        discoveredDevices.removeAll()
        discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
    
    // MARK: - Connection
    
    func connect(to device: BluetoothDevice) {
        guard let peripheral = discoveredPeripherals[device.identifier] else { return }
        isConnecting = true
        stopScanning()
        self.peripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        isConnected = false
        peripheral = nil
    }
    
    // MARK: - Commands using shared module
    
    func selectPreset(_ preset: EqPreset) {
        selectedPresetId = preset.id
        bass = Double(preset.bass)
        mid = Double(preset.mid)
        treble = Double(preset.treble)
        
        let command = BleUnifiedProtocol.shared.buildSetEqPreset(presetId: preset.id)
        sendCommand(command)
    }
    
    func sendEq() {
        // Don't send if we're updating sliders from device (encoder)
        if isUpdatingFromDevice { return }
        
        // Mark that we want to send - actual send is rate-limited to 10 Hz
        pendingEqSend = true
        
        // Start timer if not running - NO immediate send
        if eqSendTimer == nil {
            startEqSendTimer()
        }
    }
    
    private func startEqSendTimer() {
        // Fire immediately for first send, then repeat every 33ms (30 Hz)
        eqSendTimer = Timer.scheduledTimer(withTimeInterval: 0.080, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            if self.pendingEqSend {
                self.doSendEq()
                self.pendingEqSend = false
            } else {
                // No pending send for one cycle, stop timer
                timer.invalidate()
                self.eqSendTimer = nil
            }
        }
        // Fire immediately for first send
        eqSendTimer?.fire()
    }
    
    private func doSendEq() {
        // Slider is 0-24, convert to -12 to +12 dB (same as Android: progress - 12)
        let bassDb = Int32(bass) - 12
        let midDb = Int32(mid) - 12
        let trebleDb = Int32(treble) - 12
        
        let command = BleUnifiedProtocol.shared.buildSetEq(
            bass: bassDb,
            mid: midDb,
            treble: trebleDb
        )
        sendCommand(command)
    }
    
    func selectEffect(_ effect: LedEffect) {
        // Save brightness before changing to restore later if needed
        if brightness > 0 {
            savedBrightness = brightness
        }
        selectedEffect = effect
        
        // Cancel any pending delayed send
        delayedLedStateWorkItem?.cancel()
        
        // Match Android: send effect ID first, then full settings after delay
        // This avoids BLE write conflicts and matches ESP32 expectations
        doSendLedEffect()
        
        // Send full settings after 150ms delay (matching Android's handler.postDelayed)
        let workItem = DispatchWorkItem { [weak self] in
            self?.doSendLedState()
        }
        delayedLedStateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }
    
    private func doSendLedEffect() {
        // Reset the ignore timer
        lastLedSendTime = Date()
        
        // Send just the effect ID (matching Android's sendLedEffect)
        let command = BleUnifiedProtocol.shared.buildSetLedEffect(effectId: selectedEffect.id)
        sendCommand(command)
    }
    
    func sendLedBrightness() {
        // Don't send if we're updating from device (prevents feedback loop)
        if isUpdatingLedFromDevice { return }
        
        // Rate limited brightness send (for slider updates)
        pendingLedBrightnessSend = true
        if ledSendTimer == nil {
            startLedSendTimer()
        }
    }
    
    func sendLedState() {
        // Don't send if we're updating from device (prevents feedback loop)
        if isUpdatingLedFromDevice { return }
        
        // Rate limited full state send (for slider updates)
        pendingLedStateSend = true
        if ledSendTimer == nil {
            startLedSendTimer()
        }
    }
    
    private func startLedSendTimer() {
        ledSendTimer = Timer.scheduledTimer(withTimeInterval: 0.080, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            if self.pendingLedStateSend {
                self.doSendLedState()
                self.pendingLedStateSend = false
                self.pendingLedBrightnessSend = false // State includes brightness
            } else if self.pendingLedBrightnessSend {
                self.doSendLedBrightness()
                self.pendingLedBrightnessSend = false
            } else {
                timer.invalidate()
                self.ledSendTimer = nil
            }
        }
        ledSendTimer?.fire()
    }
    
    private func doSendLedBrightness() {
        // Reset the ignore timer
        lastLedSendTime = Date()
        
        // Send brightness 0-100 directly (matching Android)
        let command = BleUnifiedProtocol.shared.buildSetLedBrightness(brightness: Int32(brightness))
        sendCommand(command)
    }
    
    private func doSendLedState() {
        // Reset the ignore timer
        lastLedSendTime = Date()
        
        let (r1, g1, b1) = colorComponents(primaryColor)
        let (r2, g2, b2) = colorComponents(secondaryColor)
        
        // Send brightness/speed 0-100 directly (matching Android)
        let command = BleUnifiedProtocol.shared.buildSetLed(
            effectId: selectedEffect.id,
            brightness: Int32(brightness),
            speed: Int32(speed),
            r1: r1, g1: g1, b1: b1,
            r2: r2, g2: g2, b2: b2,
            gradient: gradientType.id
        )
        sendCommand(command)
    }
    
    func renameDevice(_ name: String) {
        deviceName = name
        let command = BleUnifiedProtocol.shared.buildSetName(name: name)
        sendCommand(command)
    }
    
    func updateControls() {
        let controlByte = ControlFlags.shared.buildControlByte(
            bassBoost: bassBoost,
            bypassDsp: bypassDsp,
            channelFlip: channelFlip,
            twsMaster: false,
            twsSlave: false,
            mute: false
        )
        let command = BleUnifiedProtocol.shared.buildSetControl(controlByte: controlByte)
        sendCommand(command)
    }
    
    // MARK: - Sound Management
    
    func sendSoundMute(_ muted: Bool) {
        soundMuted = muted
        let command = BleUnifiedProtocol.shared.buildSoundMute(muted: muted)
        sendCommand(command)
    }
    
    func deleteSound(soundType: Int) {
        let command = BleUnifiedProtocol.shared.buildSoundDelete(soundType: Int32(soundType))
        sendCommand(command)
    }
    
    func uploadSound(soundType: Int, data: Data, onProgress: @escaping (Int) -> Void, onComplete: @escaping (Bool) -> Void) {
        guard let cmdChar = cmdCharacteristic, let peripheral = peripheral else {
            onComplete(false)
            return
        }
        
        // Upload in background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fileSize = data.count
            let maxPayload = min(self.currentMtu - 3 - 4, 500) // MTU - 3 for BLE - 4 for header
            var offset = 0
            var chunkCount = 0
            let ackEveryN = 16  // ACK every 4 packets - sound files are smaller, be more careful
            var lastUiUpdate = 0
            
            // Send SOUND_BEGIN
            let beginCmd = BleUnifiedProtocol.shared.buildSoundUploadStart(soundType: Int32(soundType), size: Int32(fileSize))
            let beginData = Data(kotlinByteArray: beginCmd)
            peripheral.writeValue(beginData, for: cmdChar, type: .withResponse)
            Thread.sleep(forTimeInterval: 0.2)
            
            // Send chunks - use simple polling for flow control
            while offset < fileSize && peripheral.state == .connected {
                let remaining = fileSize - offset
                let chunkSize = min(remaining, maxPayload)
                let chunk = data.subdata(in: offset..<(offset + chunkSize))
                chunkCount += 1
                
                let dataCmd = BleUnifiedProtocol.shared.buildSoundUploadData(
                    seq: Int32(chunkCount & 0xFF),
                    data: chunk.toKotlinByteArray()
                )
                let sendData = Data(kotlinByteArray: dataCmd)
                
                // Every Nth packet use ACK to let ESP32 process and write to flash
                let useAck = (chunkCount % ackEveryN == 0)
                
                if useAck {
                    // ACK packet - gives ESP32 time to write to flash
                    peripheral.writeValue(sendData, for: cmdChar, type: .withResponse)
                    Thread.sleep(forTimeInterval: 0.005) // 5ms after ACK
                } else {
                    // No-response for speed - simple polling
                    while !peripheral.canSendWriteWithoutResponse && peripheral.state == .connected {
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                    peripheral.writeValue(sendData, for: cmdChar, type: .withoutResponse)
                    Thread.sleep(forTimeInterval: 0.002) // 2ms between packets
                }
                
                offset += chunkSize
                
                // Update UI every ~4KB (sound files are smaller than firmware)
                if offset - lastUiUpdate >= 4096 || offset >= fileSize {
                    lastUiUpdate = offset
                    let progress = min((offset * 100) / fileSize, 99)
                    DispatchQueue.main.async {
                        onProgress(progress)
                    }
                }
            }
            
            // Check if we completed or disconnected
            guard peripheral.state == .connected else {
                DispatchQueue.main.async {
                    onComplete(false)
                }
                return
            }
            
            // Wait for buffer to flush before sending END
            Thread.sleep(forTimeInterval: 0.1)
            
            // Send SOUND_END
            let endCmd = BleUnifiedProtocol.shared.buildSoundUploadEnd()
            let endData = Data(kotlinByteArray: endCmd)
            peripheral.writeValue(endData, for: cmdChar, type: .withResponse)
            
            DispatchQueue.main.async {
                onProgress(100)
                onComplete(true)
            }
        }
    }
    
    // MARK: - OTA Firmware Update
    
    func uploadFirmware(data: Data, onProgress: @escaping (Int) -> Void, onComplete: @escaping (Bool) -> Void) {
        guard let cmdChar = cmdCharacteristic, let peripheral = peripheral else {
            onComplete(false)
            return
        }
        
        // Upload in background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.otaInProgress = true
            
            let fileSize = data.count
            let maxPayload = min(self.currentMtu - 3 - 3, 500) // MTU - 3 for BLE - 3 for header
            var offset = 0
            var chunkCount = 0
            let ackEveryN = 16  // ACK every 16 packets - fewer ACKs = faster
            var lastUiUpdate = 0
            
            // Send OTA_BEGIN with response and wait
            let beginCmd = BleUnifiedProtocol.shared.buildOtaBegin(size: Int32(fileSize))
            let beginData = Data(kotlinByteArray: beginCmd)
            peripheral.writeValue(beginData, for: cmdChar, type: .withResponse)
            Thread.sleep(forTimeInterval: 0.3)
            
            // Stream chunks - use writeWithoutResponse for speed, but ACK every N for ESP32 to catch up
            while offset < fileSize && peripheral.state == .connected {
                let remaining = fileSize - offset
                let chunkSize = min(remaining, maxPayload)
                let chunk = data.subdata(in: offset..<(offset + chunkSize))
                chunkCount += 1
                
                let dataCmd = BleUnifiedProtocol.shared.buildOtaData(
                    seq: Int32(chunkCount & 0xFF),
                    data: chunk.toKotlinByteArray()
                )
                let sendData = Data(kotlinByteArray: dataCmd)
                
                // Every Nth packet use ACK to let ESP32 process and write to flash
                let useAck = (chunkCount % ackEveryN == 0)
                
                if useAck {
                    // ACK packet - gives ESP32 time to write to flash
                    peripheral.writeValue(sendData, for: cmdChar, type: .withResponse)
                } else {
                    // No-response for speed - use flow control
                    if !peripheral.canSendWriteWithoutResponse {
                        _ = self.otaWriteSemaphore.wait(timeout: .now() + 5.0)
                    }
                    peripheral.writeValue(sendData, for: cmdChar, type: .withoutResponse)
                }
                
                offset += chunkSize
                
                // Update UI every ~16KB
                if offset - lastUiUpdate >= 16384 || offset >= fileSize {
                    lastUiUpdate = offset
                    let progress = min((offset * 100) / fileSize, 99)
                    DispatchQueue.main.async {
                        onProgress(progress)
                    }
                }
            }
            
            // Check if we completed or disconnected
            guard peripheral.state == .connected else {
                self.otaInProgress = false
                DispatchQueue.main.async {
                    onComplete(false)
                }
                return
            }
            
            // Wait for buffer to flush before sending END
            Thread.sleep(forTimeInterval: 0.2)
            
            // Send OTA_END with response
            let endCmd = BleUnifiedProtocol.shared.buildOtaEnd()
            let endData = Data(kotlinByteArray: endCmd)
            peripheral.writeValue(endData, for: cmdChar, type: .withResponse)
            
            self.otaInProgress = false
            
            DispatchQueue.main.async {
                onProgress(100)
                onComplete(true)
            }
        }
    }
    
    // Called by delegate when ready to send more data
    func onReadyToSendWithoutResponse() {
        if otaInProgress {
            otaWriteSemaphore.signal()
        }
    }
    
    // MARK: - Private helpers
    
    private func sendCommand(_ data: KotlinByteArray) {
        guard let characteristic = cmdCharacteristic,
              let peripheral = peripheral else { return }
        
        let swiftData = Data(kotlinByteArray: data)
        peripheral.writeValue(swiftData, for: characteristic, type: .withResponse)
    }
    
    private func colorComponents(_ color: Color) -> (Int32, Int32, Int32) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int32(r * 255), Int32(g * 255), Int32(b * 255))
    }
    
    // MARK: - BLE Callbacks (called from delegate)
    
    func onDeviceDiscovered(_ peripheral: CBPeripheral) {
        let identifier = peripheral.identifier.uuidString
        
        // Store peripheral reference
        discoveredPeripherals[identifier] = peripheral
        
        // Check and add on main thread to avoid race conditions
        DispatchQueue.main.async {
            // Double-check on main thread to avoid duplicates
            if !self.discoveredDevices.contains(where: { $0.identifier == identifier }) {
                let name = peripheral.name ?? "Unknown Device"
                let device = BluetoothDevice(identifier: identifier, name: name)
                self.discoveredDevices.append(device)
            }
        }
    }
    
    func onConnected(_ peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.isConnecting = false
        }
        peripheral.delegate = bleDelegate
        peripheral.discoverServices([serviceUUID])
    }
    
    func onDisconnected() {
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    func onServicesDiscovered(_ peripheral: CBPeripheral, services: [CBService]) {
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([cmdUUID, statusUUID, meterUUID], for: service)
            }
        }
    }
    
    func onCharacteristicsDiscovered(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        for characteristic in characteristics {
            switch characteristic.uuid {
            case cmdUUID:
                cmdCharacteristic = characteristic
            case statusUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case meterUUID:
                meterCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        
        // Get the negotiated MTU from the peripheral
        // iOS automatically negotiates the best MTU during connection
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        DispatchQueue.main.async {
            self.currentMtu = mtu
            print("Negotiated MTU: \(mtu)")
        }
        
        // Request full status after discovery
        let command = BleUnifiedProtocol.shared.buildRequestStatus()
        sendCommand(command)
    }
    
    func onCharacteristicUpdated(_ characteristic: CBCharacteristic, data: Data) {
        if characteristic.uuid == statusUUID {
            handleStatusResponse(data)
        } else if characteristic.uuid == meterUUID {
            handleMeterData(data)
        }
    }
    
    // MARK: - Response handlers
    
    private func handleStatusResponse(_ data: Data) {
        guard data.count > 0 else { return }
        
        let responseId = Int8(bitPattern: data[0])
        let payload = data.dropFirst()
        
        switch responseId {
        case BleUnifiedProtocol.Resp.shared.STATUS_EQ:
            // Always handle EQ updates from ESP32 - the flag prevents sending back
            handleEqStatus(Array(payload))
        case BleUnifiedProtocol.Resp.shared.STATUS_LED:
            // Always handle LED updates from ESP32 - the flag prevents sending back
            handleLedStatus(Array(payload))
        case BleUnifiedProtocol.Resp.shared.STATUS_CONTROL:
            handleControlStatus(Array(payload))
        case BleUnifiedProtocol.Resp.shared.STATUS_SOUND:
            handleSoundStatus(Array(payload))
        case BleUnifiedProtocol.Resp.shared.FULL_STATUS:
            handleFullStatus(Array(payload))
        default:
            break
        }
    }
    
    private func handleSoundStatus(_ data: [UInt8]) {
        guard data.count >= 1 else { return }
        DispatchQueue.main.async {
            self.soundStatus = Int(data[0])
            print("Sound status updated: \(self.soundStatus)")
        }
    }
    
    private func handleEqStatus(_ data: [UInt8]) {
        let kotlinData = data.toKotlinByteArray()
        guard let status = BleUnifiedProtocol.shared.parseStatusEq(data: kotlinData) else { return }
        
        DispatchQueue.main.async {
            // Cancel any pending EQ sends to avoid overwriting incoming data
            self.pendingEqSend = false
            
            // Set flag to prevent onChange from calling sendEq()
            self.isUpdatingFromDevice = true
            
            // Convert -12 to +12 dB back to 0-24 slider range (dB + 12)
            self.bass = Double(status.bass + 12)
            self.mid = Double(status.mid + 12)
            self.treble = Double(status.treble + 12)
            
            // Clear flag immediately after updates (like Android's try/finally)
            self.isUpdatingFromDevice = false
        }
    }
    
    private func handleLedStatus(_ data: [UInt8]) {
        // Use shared parser for consistency with Android
        let kotlinData = data.toKotlinByteArray()
        guard let led = BleUnifiedProtocol.shared.parseStatusLed(data: kotlinData) else { return }
        
        // Debug log
        print("LED Status: effect=\(led.effectId), brightness=\(led.brightness), speed=\(led.speed)")
        
        DispatchQueue.main.async {
            // Cancel any pending delayed sends to avoid overwriting incoming data
            self.delayedLedStateWorkItem?.cancel()
            self.pendingLedStateSend = false
            self.pendingLedBrightnessSend = false
            
            // Set flag to prevent onChange from calling sendLed()
            self.isUpdatingLedFromDevice = true
            
            // Store effect ID as Int32 for Kotlin interop
            let effectId = Int32(led.effectId)
            let newEffect = LedEffect.companion.fromId(id: effectId)
            print("LED: Received effectId=\(led.effectId), parsed as Int32=\(effectId), newEffect.id=\(newEffect.id)")
            
            self.selectedEffect = newEffect
            self.brightness = Double(led.brightness)  // 0-100 (mapped in shared)
            self.speed = Double(led.speed)            // 0-100 (mapped in shared)
            
            print("LED: After update - selectedEffect.id=\(self.selectedEffect.id), brightness=\(self.brightness)")
            
            self.primaryColor = Color(
                red: Double(led.r1) / 255.0,
                green: Double(led.g1) / 255.0,
                blue: Double(led.b1) / 255.0
            )
            self.secondaryColor = Color(
                red: Double(led.r2) / 255.0,
                green: Double(led.g2) / 255.0,
                blue: Double(led.b2) / 255.0
            )
            self.gradientType = GradientType.companion.fromId(id: Int32(led.gradient))
            
            // Save brightness for restore after Off
            if self.brightness > 0 {
                self.savedBrightness = self.brightness
            }
            
            // Clear flag immediately after updates (like Android's try/finally)
            self.isUpdatingLedFromDevice = false
        }
    }
    
    private func handleControlStatus(_ data: [UInt8]) {
        guard data.count >= 1 else { return }
        let controlByte = Int32(data[0])
        DispatchQueue.main.async {
            self.bassBoost = ControlFlags.shared.isBassBoostEnabled(controlByte: controlByte)
            self.bypassDsp = ControlFlags.shared.isBypassDspEnabled(controlByte: controlByte)
            self.channelFlip = ControlFlags.shared.isChannelFlipEnabled(controlByte: controlByte)
        }
    }
    
    private func handleFullStatus(_ data: [UInt8]) {
        let kotlinData = data.toKotlinByteArray()
        if let status = BleUnifiedProtocol.shared.parseFullStatus(data: kotlinData) {
            DispatchQueue.main.async {
                print("Full status received - soundStatus: \(status.soundStatus)")
                
                // Convert -12 to +12 dB back to 0-24 slider range (dB + 12)
                self.bass = Double(status.eq.bass + 12)
                self.mid = Double(status.eq.mid + 12)
                self.treble = Double(status.eq.treble + 12)
                
                // LED state (brightness/speed are 0-100 from ESP32, matching Android)
                self.selectedEffect = LedEffect.companion.fromId(id: status.led.effectId)
                self.brightness = Double(status.led.brightness)  // 0-100 direct
                self.speed = Double(status.led.speed)            // 0-100 direct
                
                // LED colors - convert RGB bytes to Color
                self.primaryColor = Color(
                    red: Double(status.led.r1) / 255.0,
                    green: Double(status.led.g1) / 255.0,
                    blue: Double(status.led.b1) / 255.0
                )
                self.secondaryColor = Color(
                    red: Double(status.led.r2) / 255.0,
                    green: Double(status.led.g2) / 255.0,
                    blue: Double(status.led.b2) / 255.0
                )
                self.gradientType = GradientType.companion.fromId(id: status.led.gradient)
                
                // Save brightness for restore after Off
                if self.brightness > 0 {
                    self.savedBrightness = self.brightness
                }
                
                self.deviceName = status.deviceName
                self.firmwareVersion = status.firmwareVersion
                
                // Sound status (fixes not updating on first connection)
                self.soundStatus = Int(status.soundStatus)
                
                let controlByte = status.controlByte
                self.bassBoost = ControlFlags.shared.isBassBoostEnabled(controlByte: controlByte)
                self.bypassDsp = ControlFlags.shared.isBypassDspEnabled(controlByte: controlByte)
                self.channelFlip = ControlFlags.shared.isChannelFlipEnabled(controlByte: controlByte)
            }
        }
    }
    
    private func handleMeterData(_ data: Data) {
        guard data.count >= 3 else { 
            print("Meter data too short: \(data.count) bytes")
            return 
        }
        // Android uses max 120 dB: bar.progress = level.coerceIn(0, 120)
        // We normalize to 0-1 for display (level / 120)
        let l30 = min(Int(data[0]), 120)
        let l60 = min(Int(data[1]), 120)
        let l100 = min(Int(data[2]), 120)
        DispatchQueue.main.async {
            self.meterLevel1 = Double(l30) / 120.0
            self.meterLevel2 = Double(l60) / 120.0
            self.meterLevel3 = Double(l100) / 120.0
        }
    }
}

// MARK: - Separate BLE Delegate Class

class BLEDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var viewModel: ConnectionViewModel?
    let centralManager: CBCentralManager
    
    init(viewModel: ConnectionViewModel) {
        self.viewModel = viewModel
        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        self.centralManager.delegate = self
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Ready when poweredOn
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        viewModel?.onDeviceDiscovered(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        viewModel?.onConnected(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        viewModel?.onDisconnected()
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        viewModel?.onServicesDiscovered(peripheral, services: services)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        viewModel?.onCharacteristicsDiscovered(peripheral, characteristics: characteristics)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        viewModel?.onCharacteristicUpdated(characteristic, data: data)
    }
    
    // Called when notification state changes (subscribe/unsubscribe)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Notification state error for \(characteristic.uuid): \(error)")
        } else {
            print("Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
        }
    }
    
    // Called when peripheral is ready to accept more writeWithoutResponse data
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        viewModel?.onReadyToSendWithoutResponse()
    }
}

// MARK: - Data conversion helpers

extension Data {
    init(kotlinByteArray: KotlinByteArray) {
        var bytes = [UInt8]()
        for i in 0..<kotlinByteArray.size {
            bytes.append(UInt8(bitPattern: kotlinByteArray.get(index: i)))
        }
        self.init(bytes)
    }
    
    func toKotlinByteArray() -> KotlinByteArray {
        let kotlinArray = KotlinByteArray(size: Int32(count))
        for (index, byte) in enumerated() {
            kotlinArray.set(index: Int32(index), value: Int8(bitPattern: byte))
        }
        return kotlinArray
    }
}

extension Array where Element == UInt8 {
    func toKotlinByteArray() -> KotlinByteArray {
        let kotlinArray = KotlinByteArray(size: Int32(count))
        for (index, byte) in enumerated() {
            kotlinArray.set(index: Int32(index), value: Int8(bitPattern: byte))
        }
        return kotlinArray
    }
}
