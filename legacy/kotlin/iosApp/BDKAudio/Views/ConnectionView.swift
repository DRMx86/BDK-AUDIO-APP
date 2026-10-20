import SwiftUI
import CoreBluetooth
import sharedKit

struct ConnectionView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    // Scanning state
    @State private var isScanning = false
    @State private var showNoDeviceOverlay = false
    @State private var showBluetoothOffAlert = false
    @State private var scanTimeoutTimer: Timer?
    @State private var autoConnectTimer: Timer?
    @State private var autoConnectCountdown = 4
    
    // Pulse animation - just opacity, no scale to prevent movement
    @State private var pulsePhase: Double = 0.6
    
    private let scanTimeout: TimeInterval = 15.0
    private let autoConnectDelay: TimeInterval = 4.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(hex: "1a1a2e")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Pulsing glow - positioned absolutely in center-top area
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(0.9),
                                Color.cyan.opacity(0.5),
                                Color.cyan.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .opacity(pulsePhase)
                    .animation(
                        Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: pulsePhase
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.35)
                    .allowsHitTesting(false)
                
                // BDK Logo - positioned absolutely, not affected by pulse
                VStack(spacing: 4) {
                    Text("BDK")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    Text("AUDIO")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.cyan)
                        .tracking(8)
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.35)
                
                // Content area at bottom
                VStack {
                    Spacer()
                    Spacer()
                    
                    // Status text and device list area
                    VStack(spacing: 16) {
                    if viewModel.discoveredDevices.count > 1 {
                        // Multiple devices found - show list
                        Text("Found \(viewModel.discoveredDevices.count) devices")
                            .font(.headline)
                            .foregroundColor(.cyan)
                        Text("Select a device to connect")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(viewModel.discoveredDevices, id: \.identifier) { device in
                                    DeviceRow(device: device) {
                                        cancelAutoConnect()
                                        viewModel.connect(to: device)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 200)
                    } else if viewModel.discoveredDevices.count == 1 {
                        // Single device found - show with auto-connect countdown
                        Text("Found \(viewModel.discoveredDevices.first?.name ?? "device")")
                            .font(.headline)
                            .foregroundColor(.cyan)
                        Text("Auto-connecting in \(autoConnectCountdown)s... Tap to connect now")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        if let device = viewModel.discoveredDevices.first {
                            DeviceRow(device: device) {
                                cancelAutoConnect()
                                viewModel.connect(to: device)
                            }
                            .padding(.horizontal)
                        }
                    } else if isScanning {
                        // Searching
                        Text("Searching for devices...")
                            .font(.headline)
                            .foregroundColor(.cyan)
                        Text("Make sure your speaker is powered on")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            .scaleEffect(1.2)
                            .padding(.top, 8)
                    } else {
                        // Not scanning
                        Text("Connect to your speaker")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    }
                    .frame(height: 180)
                    
                    Spacer()
                } // End of content VStack
            
            // No Device Found Overlay
            if showNoDeviceOverlay {
                NoDeviceOverlay(
                    onRetry: {
                        hideNoDeviceOverlay()
                        startScanning()
                    },
                    onManualSelect: {
                        hideNoDeviceOverlay()
                        // Could show a manual entry or just restart scan
                        startScanning()
                    }
                )
                .transition(.opacity)
            }
        } // End of ZStack
        } // End of GeometryReader
        .navigationBarHidden(true)
        .onAppear {
            startPulseAnimation()
            checkBluetoothAndScan()
        }
        .onDisappear {
            stopScanning()
        }
        .alert("Bluetooth is Off", isPresented: $showBluetoothOffAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please turn on Bluetooth to connect to your BDK speaker.")
        }
        .onChange(of: viewModel.discoveredDevices.count) { oldCount, newCount in
            handleDeviceCountChange(oldCount: oldCount, newCount: newCount)
        }
    }
    
    // MARK: - Bluetooth Check
    
    private func checkBluetoothAndScan() {
        // Check if Bluetooth is on
        if viewModel.centralManager.state == .poweredOn {
            startScanning()
        } else if viewModel.centralManager.state == .poweredOff {
            showBluetoothOffAlert = true
        } else {
            // Wait a moment for Bluetooth to initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if viewModel.centralManager.state == .poweredOn {
                    startScanning()
                } else if viewModel.centralManager.state == .poweredOff {
                    showBluetoothOffAlert = true
                }
            }
        }
    }
    
    // MARK: - Scanning
    
    private func startScanning() {
        guard viewModel.centralManager.state == .poweredOn else {
            showBluetoothOffAlert = true
            return
        }
        
        isScanning = true
        showNoDeviceOverlay = false
        viewModel.startScanning()
        startPulseAnimation()
        
        // Start scan timeout
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: scanTimeout, repeats: false) { _ in
            handleScanTimeout()
        }
    }
    
    private func stopScanning() {
        isScanning = false
        viewModel.stopScanning()
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        cancelAutoConnect()
    }
    
    private func handleScanTimeout() {
        stopScanning()
        
        if viewModel.discoveredDevices.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                showNoDeviceOverlay = true
            }
            stopPulseAnimation()
        } else if viewModel.discoveredDevices.count == 1 {
            // Auto-connect to the only device
            if let device = viewModel.discoveredDevices.first {
                viewModel.connect(to: device)
            }
        }
    }
    
    // MARK: - Auto-Connect
    
    private func handleDeviceCountChange(oldCount: Int, newCount: Int) {
        if newCount == 1 && oldCount == 0 {
            // First device found - start auto-connect countdown
            startAutoConnectCountdown()
        } else if newCount > 1 {
            // Multiple devices - cancel auto-connect
            cancelAutoConnect()
        }
    }
    
    private func startAutoConnectCountdown() {
        autoConnectCountdown = 4
        
        autoConnectTimer?.invalidate()
        autoConnectTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            autoConnectCountdown -= 1
            
            if autoConnectCountdown <= 0 {
                timer.invalidate()
                autoConnectTimer = nil
                
                // Auto-connect if still only 1 device
                if viewModel.discoveredDevices.count == 1,
                   let device = viewModel.discoveredDevices.first {
                    stopScanning()
                    viewModel.connect(to: device)
                }
            }
        }
    }
    
    private func cancelAutoConnect() {
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        autoConnectCountdown = 4
    }
    
    // MARK: - No Device Overlay
    
    private func hideNoDeviceOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showNoDeviceOverlay = false
        }
        startPulseAnimation()
    }
    
    // MARK: - Pulse Animation
    
    private func startPulseAnimation() {
        // Just set to 1.0 - the .animation modifier on the Circle handles the animation
        pulsePhase = 1.0
    }
    
    private func stopPulseAnimation() {
        pulsePhase = 0.4
    }
}

// MARK: - No Device Overlay

struct NoDeviceOverlay: View {
    let onRetry: () -> Void
    let onManualSelect: () -> Void
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            // Card
            VStack(spacing: 20) {
                // Bluetooth off icon
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                
                Text("No Device Found")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text("Make sure your BDK speaker is:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint(text: "Powered on")
                    BulletPoint(text: "In pairing mode (LED blinking)")
                    BulletPoint(text: "Within Bluetooth range")
                    BulletPoint(text: "Not connected to another device")
                }
                .padding(.horizontal)
                
                // Buttons
                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "E0B0FF")) // Light purple like Android
                            .cornerRadius(12)
                    }
                    
                    Button(action: onManualSelect) {
                        Text("Select Manually")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "E0B0FF").opacity(0.7))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(24)
            .background(Color(hex: "2a2a3e"))
            .cornerRadius(20)
            .padding(.horizontal, 40)
        }
    }
}

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.gray)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: BluetoothDevice
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "hifispeaker.fill")
                    .foregroundColor(.cyan)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Tap to connect")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - BluetoothDevice Model

struct BluetoothDevice: Identifiable {
    let identifier: String
    let name: String
    
    var id: String { identifier }
}
