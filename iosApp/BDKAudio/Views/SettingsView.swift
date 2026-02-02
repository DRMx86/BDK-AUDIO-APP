import SwiftUI
import sharedKit

// MARK: - Settings View (matching Android SettingsActivity exactly)

struct SettingsView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var deviceNameInput: String = ""
    @State private var showDeviceInfo = false
    @State private var showOtaView = false
    @State private var showAppInfo = false
    @State private var showRenameSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background matching app theme
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(hex: "1a1a2e")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "arrow.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            Text("Settings")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            // Invisible spacer for centering
                            Color.clear.frame(width: 28)
                        }
                        .padding()
                        
                        // Settings groups
                        VStack(spacing: 24) {
                            // Audio Settings Group
                            SettingsGroupView(title: "AUDIO") {
                                VStack(spacing: 0) {
                                    SettingsToggleRow(
                                        title: "Bass Boost",
                                        subtitle: "Extra low frequency enhancement",
                                        icon: "speaker.wave.3.fill",
                                        isOn: $viewModel.bassBoost
                                    ) {
                                        viewModel.updateControls()
                                    }
                                    
                                    Divider().background(Color.gray.opacity(0.3))
                                    
                                    SettingsToggleRow(
                                        title: "Bypass DSP",
                                        subtitle: "Disable all audio processing",
                                        icon: "waveform.path",
                                        isOn: $viewModel.channelFlip
                                    ) {
                                        viewModel.updateControls()
                                    }
                                    
                                    Divider().background(Color.gray.opacity(0.3))
                                    
                                    SettingsToggleRow(
                                        title: "Channel Flip",
                                        subtitle: "Swap left and right channels",
                                        icon: "arrow.left.arrow.right",
                                        isOn: $viewModel.bypassDsp
                                    ) {
                                        viewModel.updateControls()
                                    }
                                }
                            }
                            
                            // Device Settings Group
                            SettingsGroupView(title: "DEVICE") {
                                VStack(spacing: 0) {
                                    // Device Name
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "speaker.fill")
                                                .foregroundColor(.cyan)
                                                .frame(width: 24)
                                            Text("Device Name")
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .padding(.horizontal)
                                        .padding(.top, 12)
                                        
                                        HStack {
                                            TextField("", text: $deviceNameInput)
                                                .textFieldStyle(PlainTextFieldStyle())
                                                .padding(10)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(8)
                                                .foregroundColor(.white)
                                                .autocapitalization(.none)
                                            
                                            Button(action: applyDeviceName) {
                                                Text("Apply")
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.black)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 10)
                                                    .background(Color.cyan)
                                                    .cornerRadius(8)
                                            }
                                        }
                                        .padding(.horizontal)
                                        .padding(.bottom, 12)
                                    }
                                    
                                    Divider().background(Color.gray.opacity(0.3))
                                    
                                    // Device Info
                                    SettingsButtonRow(
                                        title: "Device Info",
                                        subtitle: "View device details & sounds",
                                        icon: "info.circle"
                                    ) {
                                        showDeviceInfo = true
                                    }
                                }
                            }
                            
                            // System Group
                            SettingsGroupView(title: "SYSTEM") {
                                VStack(spacing: 0) {
                                    // Connect to Other Device
                                    SettingsButtonRow(
                                        title: "Connect to Other Device",
                                        subtitle: "Scan for different speaker",
                                        icon: "arrow.triangle.2.circlepath"
                                    ) {
                                        viewModel.disconnect()
                                        dismiss()
                                    }
                                    
                                    Divider().background(Color.gray.opacity(0.3))
                                    
                                    // Firmware Update
                                    SettingsButtonRow(
                                        title: "Firmware Update",
                                        subtitle: "Current: \(viewModel.firmwareVersion)",
                                        icon: "arrow.down.circle"
                                    ) {
                                        showOtaView = true
                                    }
                                    
                                    Divider().background(Color.gray.opacity(0.3))
                                    
                                    // App Info
                                    SettingsButtonRow(
                                        title: "App Info",
                                        subtitle: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")",
                                        icon: "apps.iphone"
                                    ) {
                                        showAppInfo = true
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                deviceNameInput = viewModel.deviceName
            }
            .sheet(isPresented: $showDeviceInfo) {
                DeviceInfoSheet(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $showOtaView) {
                OtaView(viewModel: viewModel)
            }
            .sheet(isPresented: $showAppInfo) {
                AppInfoView()
            }
            .alert("Name Applied", isPresented: $showRenameSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Device will restart with the new name.")
            }
        }
    }
    
    private func applyDeviceName() {
        let trimmed = deviceNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.renameDevice(trimmed)
        showRenameSuccess = true
    }
}

// MARK: - Settings Group Container

struct SettingsGroupView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .tracking(2)
                .padding(.horizontal, 4)
            
            content
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
        }
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    let onChanged: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .cyan))
                .labelsHidden()
                .onChange(of: isOn) { _, _ in
                    onChanged()
                }
        }
        .padding()
    }
}

// MARK: - Settings Button Row

struct SettingsButtonRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.cyan)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
        }
    }
}

// MARK: - Previews

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: ConnectionViewModel())
    }
}
