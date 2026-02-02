import SwiftUI
import sharedKit

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct MainControlView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hex: "1a1a2e")]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HeaderView(viewModel: viewModel)
                
                // Content based on selected tab with smooth transition
                ZStack {
                    SoundTabView(viewModel: viewModel)
                        .opacity(selectedTab == 0 ? 1 : 0)
                        .offset(x: selectedTab == 0 ? 0 : -30)
                    
                    LedTabView(viewModel: viewModel)
                        .opacity(selectedTab == 1 ? 1 : 0)
                        .offset(x: selectedTab == 1 ? 0 : 30)
                }
                .animation(.easeInOut(duration: 0.25), value: selectedTab)
                
                // Bottom tab bar (like Android)
                BottomTabBar(selectedTab: $selectedTab)
            }
        }
        .navigationBarHidden(true)
    }
}

struct HeaderView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var showSettings = false
    
    var body: some View {
        HStack {
            // Device name and status
            VStack(alignment: .leading) {
                Text(viewModel.deviceName)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if !viewModel.codecName.isEmpty {
                        Text("•")
                            .foregroundColor(.gray)
                        Text(viewModel.codecName)
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                }
            }
            
            Spacer()
            
            // Settings button
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
        .padding()
    }
}

struct BottomTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            BottomTabButton(title: "Sound", icon: "house.fill", isSelected: selectedTab == 0) {
                withAnimation(.spring()) { selectedTab = 0 }
            }
            
            BottomTabButton(title: "LED", icon: "lightbulb.fill", isSelected: selectedTab == 1) {
                withAnimation(.spring()) { selectedTab = 1 }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.black.opacity(0.95))
    }
}

struct BottomTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .cyan : .gray)
            .frame(maxWidth: .infinity)
        }
    }
}

// Keep for backwards compatibility
struct TabSelectorView: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        EmptyView()
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .foregroundColor(isSelected ? .black : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.cyan : Color.clear)
            .cornerRadius(10)
        }
    }
}

// Placeholder views - will be fully implemented
struct SoundTabView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    // Helper to get preset name by ID
    private var currentPresetName: String {
        let allPresets: [(id: Int32, name: String)] = [
            (0, "Balanced"), (1, "Deep Bass"), (2, "Vocals"),
            (3, "Bright"), (4, "Punchy"), (5, "Warm"),
            (6, "Studio"), (7, "Club"), (8, "Gaming"),
            (9, "Custom 1"), (10, "Custom 2")
        ]
        return allPresets.first { $0.id == viewModel.selectedPresetId }?.name ?? "Balanced"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Sound Profile header - matching Android layout exactly
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SOUND PROFILE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                        Text(currentPresetName)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                    }
                    Spacer()
                    
                    // Codec badge like Android (aptX, LDAC, etc)
                    if !viewModel.codecName.isEmpty {
                        Text(viewModel.codecName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.gray.opacity(0.4))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Level meters (matching Android - horizontal bars side by side)
                LevelMetersView(viewModel: viewModel)
                
                // EQ section (always visible - on top)
                EQView(viewModel: viewModel)
                
                // EQ Presets section (below EQ)
                EQPresetsView(viewModel: viewModel)
            }
            .padding()
        }
    }
}

// LedTabView is now in LedViews.swift

// Placeholder implementations
struct EQPresetsView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var showMorePresets = false
    
    // Define presets inline to match Android exactly
    struct PresetData: Identifiable {
        let id: Int32
        let name: String
        let icon: String
        let bass: Int32
        let mid: Int32
        let treble: Int32
    }
    
    // Main presets (always visible) - matching Android exactly
    let mainPresets: [PresetData] = [
        PresetData(id: 0, name: "Balanced", icon: "⚖️", bass: 50, mid: 50, treble: 50),
        PresetData(id: 1, name: "Deep Bass", icon: "🔊", bass: 85, mid: 45, treble: 40),
        PresetData(id: 2, name: "Vocals", icon: "🎤", bass: 40, mid: 70, treble: 55),
        PresetData(id: 3, name: "Bright", icon: "✨", bass: 45, mid: 55, treble: 80),
        PresetData(id: 4, name: "Punchy", icon: "💥", bass: 75, mid: 40, treble: 70),
        PresetData(id: 5, name: "Warm", icon: "🌅", bass: 65, mid: 55, treble: 35)
    ]
    
    // Extended presets (shown when "More Presets" is tapped)
    let morePresets: [PresetData] = [
        PresetData(id: 6, name: "Studio", icon: "🎧", bass: 50, mid: 52, treble: 50),
        PresetData(id: 7, name: "Club", icon: "🎉", bass: 80, mid: 45, treble: 65),
        PresetData(id: 8, name: "Gaming", icon: "🎮", bass: 75, mid: 55, treble: 70),
        PresetData(id: 9, name: "Custom 1", icon: "⭐", bass: 50, mid: 50, treble: 50),
        PresetData(id: 10, name: "Custom 2", icon: "⭐", bass: 50, mid: 50, treble: 50)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EQ Presets")
                .font(.headline)
                .foregroundColor(.white)
            
            // Main preset grid (2 rows x 3 columns)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(mainPresets) { preset in
                    PresetGridButton(
                        name: preset.name,
                        icon: preset.icon,
                        isSelected: viewModel.selectedPresetId == preset.id
                    ) {
                        selectPreset(preset)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                            if preset.id == 9 || preset.id == 10 { // Custom presets
                                saveCustomPreset(preset.id)
                            }
                        }
                    )
                }
            }
            
            // More presets expandable - matching Android "More presets ▼"
            Button(action: { withAnimation { showMorePresets.toggle() } }) {
                Text(showMorePresets ? "More presets ▲" : "More presets ▼")
                    .font(.subheadline)
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .padding(.vertical, 4)
            
            if showMorePresets {
                // Row 3: Studio, Club, Gaming
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(morePresets.prefix(3), id: \.id) { preset in
                        PresetGridButton(
                            name: preset.name,
                            icon: preset.icon,
                            isSelected: viewModel.selectedPresetId == preset.id
                        ) {
                            selectPreset(preset)
                        }
                    }
                }
                
                // Row 4: Custom 1, Custom 2, empty
                HStack(spacing: 12) {
                    ForEach(morePresets.suffix(2), id: \.id) { preset in
                        PresetGridButton(
                            name: preset.name,
                            icon: preset.icon,
                            isSelected: viewModel.selectedPresetId == preset.id
                        ) {
                            selectPreset(preset)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                                saveCustomPreset(preset.id)
                            }
                        )
                    }
                    // Empty cell to maintain 3-column layout
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    private func selectPreset(_ preset: PresetData) {
        // Convert 0-100 preset values to 0-24 slider range (same as Android)
        // Formula: ((value - 50) * 12 / 50) + 12 = dB + 12
        let bassSlider = Double((preset.bass - 50) * 12 / 50 + 12)
        let midSlider = Double((preset.mid - 50) * 12 / 50 + 12)
        let trebleSlider = Double((preset.treble - 50) * 12 / 50 + 12)
        
        // Update all values atomically to prevent UI jumping
        withAnimation(.none) {
            viewModel.selectedPresetId = preset.id
            viewModel.bass = bassSlider
            viewModel.mid = midSlider
            viewModel.treble = trebleSlider
        }
        // Send after state is set
        viewModel.sendEq()
    }
    
    private func saveCustomPreset(_ id: Int32) {
        // Save current EQ values to custom preset
        // TODO: Persist to UserDefaults with key "custom_\(id)"
        viewModel.selectedPresetId = id
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

struct PresetGridButton: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(icon)
                    .font(.title2)
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .black : .white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(isSelected ? Color.cyan : Color.white.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2)
            )
        }
    }
}

struct PresetButton: View {
    let preset: EqPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(preset.icon)
                    .font(.title)
                Text(preset.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? .black : .white)
            }
            .frame(width: 80, height: 80)
            .background(isSelected ? Color.cyan : Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct EQView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.cyan)
                Text("EQ")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 16) {
                EqSlider(
                    title: "Bass",
                    value: $viewModel.bass,
                    color: .orange,
                    onChanged: { viewModel.sendEq() }
                )
                EqSlider(
                    title: "Mid",
                    value: $viewModel.mid,
                    color: .cyan,
                    onChanged: { viewModel.sendEq() }
                )
                EqSlider(
                    title: "Treble",
                    value: $viewModel.treble,
                    color: .green,
                    onChanged: { viewModel.sendEq() }
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

// Keep for backwards compatibility
struct FineTuneView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    var body: some View {
        EQView(viewModel: viewModel)
    }
}

struct EqSlider: View {
    let title: String
    @Binding var value: Double
    let color: Color
    let onChanged: () -> Void
    
    // Convert 0-24 to -12 to +12 dB for display (same as Android: progress - 12)
    private var dbValue: Int {
        Int(value) - 12
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(width: 60, alignment: .leading)
                
                Spacer()
                
                Text("\(dbValue > 0 ? "+" : "")\(dbValue) dB")
                    .font(.caption)
                    .foregroundColor(.cyan)
                    .frame(width: 50, alignment: .trailing)
            }
            
            Slider(value: $value, in: 0...24, step: 1)
                .tint(color)
                .animation(.none, value: value)  // Disable momentum/animation
                .onChange(of: value) { oldValue, newValue in
                    onChanged()
                }
        }
    }
}

struct LevelMetersView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    // Convert 0-1 level back to dB (0-120 range)
    private func levelToDb(_ level: Double) -> Int {
        Int(level * 120)
    }
    
    var body: some View {
        // Level meters matching Android layout exactly
        // Horizontal bars side by side with dB labels below
        HStack(spacing: 8) {
            MeterColumn(dbValue: levelToDb(viewModel.meterLevel1), level: viewModel.meterLevel1, color: .orange)
            MeterColumn(dbValue: levelToDb(viewModel.meterLevel2), level: viewModel.meterLevel2, color: .cyan)
            MeterColumn(dbValue: levelToDb(viewModel.meterLevel3), level: viewModel.meterLevel3, color: .green)
        }
        .frame(height: 24)
        .padding(.horizontal)
    }
}

struct MeterColumn: View {
    let dbValue: Int
    let level: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.3))
                    
                    // Filled portion
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * level))
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(height: 8)
            
            // Dynamic dB label below
            Text("\(dbValue)dB")
                .font(.caption2)
                .foregroundColor(color)
        }
    }
}

// Keep for backwards compatibility but not used
struct HorizontalMeterBar: View {
    let label: String
    let level: Double
    let color: Color
    
    var body: some View {
        EmptyView()
    }
}

// Keep old vertical meter for reference
struct MeterBar: View {
    let label: String
    let level: Double
    let color: Color
    
    var body: some View {
        VStack {
            GeometryReader { geo in
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(color)
                        .frame(height: geo.size.height * level)
                        .cornerRadius(4)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

// NOTE: DeviceInfoSheet, SettingsView, OtaView, and AppInfoView are now in separate files:
// - Views/DeviceInfoSheet.swift
// - Views/SettingsView.swift
// - Views/OtaView.swift
// - Views/AppInfoView.swift
