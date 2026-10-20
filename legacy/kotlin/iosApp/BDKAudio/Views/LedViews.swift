import SwiftUI
import sharedKit

// Effect names matching ESP32 (index = effect ID)
private let effectNames = [
    "Spectrum Bars",      // 0
    "Beat Pulse",         // 1
    "Ripple",             // 2
    "Fire",               // 3
    "Plasma",             // 4
    "Matrix Rain",        // 5
    "VU Meter",           // 6
    "Starfield",          // 7
    "Wave",               // 8
    "Fireworks",          // 9
    "Rainbow Wave",       // 10
    "Particle Burst",     // 11
    "Kaleidoscope",       // 12
    "Frequency Spiral",   // 13
    "Bass Reactor",       // 14
    "Meteor Shower",      // 15
    "Breathing",          // 16
    "DNA Helix",          // 17
    "Audio Scope",        // 18
    "Bouncing Balls",     // 19
    "Lava Lamp",          // 20
    "Ambient"             // 21
]

private func getEffectName(_ id: Int) -> String {
    if id == 255 { return "Off" }
    return id < effectNames.count ? effectNames[id] : "Effect \(id)"
}

private func getEffectEmoji(_ id: Int) -> String {
    let emojis = ["📊", "💓", "🌊", "🔥", "🟣", "💚", "📶", "⭐", "〰️", "🎆",
                  "🌈", "💥", "🔮", "🌀", "🎵", "☄️", "💨", "🧬", "📈", "⚽", "🫧", "✨"]
    if id == 255 { return "⭕" }
    return id < emojis.count ? emojis[id] : "🎨"
}

// MARK: - LED Tab View (Main container matching Android layout)

struct LedTabView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @State private var isEffectListExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // LED EFFECT header
                VStack(alignment: .leading, spacing: 4) {
                    Text("LED EFFECT")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .tracking(2)
                    
                    Text(getEffectName(Int(viewModel.selectedEffect.id)))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Glass card container with animated background (like Android)
                ZStack {
                    // Animated effect background - clipped to card shape
                    LedEffectBackground(effectId: Int(viewModel.selectedEffect.id))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // Glass overlay for content visibility
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                    
                    // Content
                    VStack(spacing: 20) {
                        // Effect selector (expandable dropdown)
                        EffectDropdownView(
                            viewModel: viewModel,
                            isExpanded: $isEffectListExpanded
                        )
                        
                        // Quick Select grid
                        QuickSelectGrid(viewModel: viewModel)
                        
                        // Brightness slider
                        BrightnessSliderView(viewModel: viewModel)
                        
                        // Ambient controls (only visible for Ambient effect, id=21)
                        if viewModel.selectedEffect.id == 21 {
                            AmbientControlsView(viewModel: viewModel)
                        }
                    }
                    .padding()
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color.black)
    }
}

// MARK: - Effect Dropdown View

struct EffectDropdownView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @Binding var isExpanded: Bool
    
    // Effect IDs for the full list (0-21, excluding OFF=255)
    private let effectIds: [Int32] = Array(0...21).map { Int32($0) }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (current selection)
            Button(action: { withAnimation(.spring()) { isExpanded.toggle() } }) {
                HStack {
                    Text(getEffectName(Int(viewModel.selectedEffect.id)))
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Expandable list
            if isExpanded {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(effectIds, id: \.self) { effectId in
                            let effect = LedEffect.companion.fromId(id: effectId)
                            EffectListRow(
                                effect: effect,
                                isSelected: viewModel.selectedEffect.id == effectId
                            ) {
                                viewModel.selectEffect(effect)
                                withAnimation { isExpanded = false }
                            }
                            
                            if effectId != 21 { // Not the last one (Ambient)
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
            }
        }
    }
}

struct EffectListRow: View {
    let effect: LedEffect
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(getEffectEmoji(Int(effect.id)))
                    .font(.title2)
                
                Text(getEffectName(Int(effect.id)))
                    .font(.body)
                    .foregroundColor(isSelected ? .cyan : .white)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.cyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.cyan.opacity(0.1) : Color.clear)
        }
    }
}

// MARK: - Quick Select Grid

struct QuickSelectGrid: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    // Quick select buttons matching Android layout (using IDs to avoid framework version issues)
    // 0=Spectrum, 1=Beat Pulse, 14=Bass Reactor, 10=Rainbow Wave, 21=Ambient, 255=Off
    private var quickEffects: [(effect: LedEffect, label: String, isOff: Bool)] {
        [
            (LedEffect.companion.fromId(id: 0), "Spectrum", false),
            (LedEffect.companion.fromId(id: 1), "Beat Pulse", false),
            (LedEffect.companion.fromId(id: 14), "Bass", false),
            (LedEffect.companion.fromId(id: 10), "Rainbow", false),
            (LedEffect.companion.fromId(id: 21), "Ambient", false),
            (LedEffect.companion.fromId(id: 255), "Off", true)
        ]
    }
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK SELECT")
                .font(.caption)
                .foregroundColor(.gray)
                .tracking(2)
            
            LazyVGrid(columns: columns, spacing: 12) {
                // Use label as unique identifier since effect.id might have issues with Kotlin interop
                ForEach(quickEffects, id: \.label) { item in
                    QuickSelectButton(
                        emoji: getEffectEmoji(Int(item.effect.id)),
                        label: item.label,
                        isSelected: isButtonSelected(item),
                        isOff: item.isOff
                    ) {
                        handleQuickSelect(item.effect, isOff: item.isOff)
                    }
                }
            }
        }
    }
    
    private func handleQuickSelect(_ effect: LedEffect, isOff: Bool) {
        if isOff {
            // Turn off by setting brightness to 0 (like Android)
            viewModel.brightness = 0
            viewModel.sendLedBrightness()
        } else {
            // Restore brightness if it was off
            if viewModel.brightness == 0 {
                viewModel.brightness = viewModel.savedBrightness > 0 ? viewModel.savedBrightness : 80
            }
            viewModel.selectEffect(effect)
        }
    }
    
    private func isButtonSelected(_ item: (effect: LedEffect, label: String, isOff: Bool)) -> Bool {
        if item.isOff {
            // Off button is selected when brightness is 0
            return viewModel.brightness == 0
        } else {
            // Other buttons are selected when effect ID matches AND brightness > 0
            return viewModel.selectedEffect.id == item.effect.id && viewModel.brightness > 0
        }
    }
}

struct QuickSelectButton: View {
    let emoji: String
    let label: String
    let isSelected: Bool
    let isOff: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if isOff {
                    // Special "Off" button with circle icon
                    Circle()
                        .stroke(Color.red.opacity(0.6), lineWidth: 2)
                        .frame(width: 30, height: 30)
                } else {
                    Text(emoji)
                        .font(.title)
                }
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Brightness Slider

struct BrightnessSliderView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BRIGHTNESS")
                .font(.caption)
                .foregroundColor(.gray)
                .tracking(2)
            
            HStack(spacing: 12) {
                Slider(
                    value: $viewModel.brightness,
                    in: 0...100,
                    step: 1
                )
                .tint(.cyan)
                .animation(.none, value: viewModel.brightness)
                .onChange(of: viewModel.brightness) { _, _ in
                    viewModel.sendLedBrightness()
                }
                
                Text("\(Int(viewModel.brightness))")
                    .font(.headline)
                    .foregroundColor(.cyan)
                    .frame(width: 40, alignment: .trailing)
                    .animation(.none, value: viewModel.brightness)
            }
        }
    }
}

// MARK: - Ambient Controls (Speed, Colors, Gradient)

struct AmbientControlsView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Animation Speed
            VStack(alignment: .leading, spacing: 8) {
                Text("ANIMATION SPEED")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .tracking(2)
                
                HStack(spacing: 12) {
                    Slider(
                        value: $viewModel.speed,
                        in: 0...100,
                        step: 1
                    )
                    .tint(.cyan)
                    .animation(.none, value: viewModel.speed)
                    .onChange(of: viewModel.speed) { _, _ in
                        viewModel.sendLedState()
                    }
                    
                    Text("\(Int(viewModel.speed))")
                        .font(.headline)
                        .foregroundColor(.cyan)
                        .frame(width: 40, alignment: .trailing)
                        .animation(.none, value: viewModel.speed)
                }
            }
            
            // Colors
            VStack(alignment: .leading, spacing: 8) {
                Text("COLORS")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .tracking(2)
                
                HStack(spacing: 16) {
                    VStack {
                        Text("Primary")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        ColorPicker("", selection: $viewModel.primaryColor)
                            .labelsHidden()
                            .frame(height: 50)
                            .onChange(of: viewModel.primaryColor) { _, _ in
                                viewModel.sendLedState()
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    
                    VStack {
                        Text("Secondary")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        ColorPicker("", selection: $viewModel.secondaryColor)
                            .labelsHidden()
                            .frame(height: 50)
                            .onChange(of: viewModel.secondaryColor) { _, _ in
                                viewModel.sendLedState()
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
            }
            
            // Gradient type picker
            VStack(alignment: .leading, spacing: 8) {
                Text("GRADIENT")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .tracking(2)
                
                GradientPicker(selectedGradient: $viewModel.gradientType)
                    .onChange(of: viewModel.gradientType) { _, _ in
                        viewModel.sendLedState()
                    }
            }
        }
    }
}

struct GradientPicker: View {
    @Binding var selectedGradient: GradientType
    @State private var isExpanded = false
    
    // Gradient types: 0=None, 1=Horizontal, 2=Vertical, 3=Radial, 4=Diagonal
    private let gradientOptions: [(id: Int32, name: String)] = [
        (0, "None"),
        (1, "Horizontal"),
        (2, "Vertical"),
        (3, "Radial"),
        (4, "Diagonal")
    ]
    
    private var selectedName: String {
        gradientOptions.first { $0.id == selectedGradient.id }?.name ?? "None"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header button
            Button(action: { withAnimation(.spring()) { isExpanded.toggle() } }) {
                HStack {
                    Text(selectedName)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Expandable options
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(gradientOptions, id: \.id) { option in
                        Button(action: {
                            selectedGradient = GradientType.companion.fromId(id: option.id)
                            withAnimation { isExpanded = false }
                        }) {
                            HStack {
                                Text(option.name)
                                    .foregroundColor(selectedGradient.id == option.id ? .cyan : .white)
                                Spacer()
                                if selectedGradient.id == option.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.cyan)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedGradient.id == option.id ? Color.cyan.opacity(0.1) : Color.clear)
                        }
                        
                        if option.id != 4 {
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }
                }
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - LED Effect Background Animation

// MARK: - LED Effect Background (matches Android LedEffectPreviewView)

struct LedEffectBackground: View {
    let effectId: Int
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            Canvas { context, size in
                let frameCount = Int(timeline.date.timeIntervalSinceReferenceDate * 30)
                let t = Float(frameCount) * 0.05
                
                // Simulated audio levels (matching Android)
                let bassLevel = Float(0.3 + 0.35 * sin(Double(t) * 0.7))
                let midLevel = Float(0.25 + 0.25 * sin(Double(t) * 1.1 + 1))
                let highLevel = Float(0.15 + 0.2 * sin(Double(t) * 1.5 + 2))
                
                let state = EffectState(
                    frameCount: frameCount,
                    bassLevel: bassLevel,
                    midLevel: midLevel,
                    highLevel: highLevel
                )
                
                drawEffect(context: context, size: size, state: state)
            }
        }
        .blur(radius: 25) // Match Android's 25f blur radius
        .opacity(0.7)
    }
    
    private struct EffectState {
        let frameCount: Int
        let bassLevel: Float
        let midLevel: Float
        let highLevel: Float
        
        var phase: Double { Double(frameCount % 90) / 90.0 }
    }
    
    private func drawEffect(context: GraphicsContext, size: CGSize, state: EffectState) {
        switch effectId {
        case 0: drawSpectrumBars(context: context, size: size, state: state)
        case 1: drawBeatPulse(context: context, size: size, state: state)
        case 2: drawRipple(context: context, size: size, state: state)
        case 3: drawFire(context: context, size: size, state: state)
        case 4: drawPlasma(context: context, size: size, state: state)
        case 5: drawMatrixRain(context: context, size: size, state: state)
        case 6: drawVuMeter(context: context, size: size, state: state)
        case 7: drawStarfield(context: context, size: size, state: state)
        case 8: drawWave(context: context, size: size, state: state)
        case 9: drawFireworks(context: context, size: size, state: state)
        case 10: drawRainbowWave(context: context, size: size, state: state)
        case 11: drawParticleBurst(context: context, size: size, state: state)
        case 12: drawKaleidoscope(context: context, size: size, state: state)
        case 13: drawFrequencySpiral(context: context, size: size, state: state)
        case 14: drawBassReactor(context: context, size: size, state: state)
        case 15: drawMeteorShower(context: context, size: size, state: state)
        case 16: drawBreathing(context: context, size: size, state: state)
        case 17: drawDnaHelix(context: context, size: size, state: state)
        case 18: drawAudioScope(context: context, size: size, state: state)
        case 19: drawBouncingBalls(context: context, size: size, state: state)
        case 20: drawLavaLamp(context: context, size: size, state: state)
        case 21: drawAmbient(context: context, size: size, state: state)
        case 255: drawOff(context: context, size: size)
        default: drawDefaultGradient(context: context, size: size, state: state)
        }
    }
    
    // MARK: - Effect 0: Spectrum Bars
    private func drawSpectrumBars(context: GraphicsContext, size: CGSize, state: EffectState) {
        let barCount = 16
        let barWidth = size.width / CGFloat(barCount)
        
        for i in 0..<barCount {
            let level = CGFloat(0.2 + 0.6 * sin(state.phase * .pi * 2 + Double(i) * 0.4) * Double(state.bassLevel + 0.5))
            let barHeight = size.height * level.clamped(to: 0...1)
            
            // Color: green -> yellow -> red based on height
            let hue = (0.33 - level * 0.33).clamped(to: 0...0.33)
            let color = Color(hue: hue, saturation: 1, brightness: 1)
            
            let rect = CGRect(x: CGFloat(i) * barWidth, y: size.height - barHeight, width: barWidth - 1, height: barHeight)
            context.fill(Path(rect), with: .color(color))
            
            // Peak line
            let peakY = size.height - size.height * (level + 0.05).clamped(to: 0...1)
            context.fill(Path(CGRect(x: CGFloat(i) * barWidth, y: peakY, width: barWidth - 1, height: 2)), with: .color(.white))
        }
    }
    
    // MARK: - Effect 1: Beat Pulse
    private func drawBeatPulse(context: GraphicsContext, size: CGSize, state: EffectState) {
        let beat = (state.frameCount % 30) < 5
        let pulseLevel = beat ? 1.0 : (1.0 - Double(state.frameCount % 30) / 30.0) * 0.3
        let hue = Double(state.frameCount * 3 % 360) / 360.0
        
        // Background
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(hue: (hue + 0.35).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 0.15)))
        
        // Pulse overlay
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(hue: hue, saturation: 1, brightness: 1).opacity(pulseLevel)))
    }
    
    // MARK: - Effect 2: Ripple
    private func drawRipple(context: GraphicsContext, size: CGSize, state: EffectState) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = max(size.width, size.height) * 0.7
        
        for i in 0..<5 {
            let ripplePhase = (state.phase + Double(i) * 0.2).truncatingRemainder(dividingBy: 1.0)
            let radius = maxRadius * CGFloat(ripplePhase)
            let opacity = 1.0 - ripplePhase
            let hue = Double(i) * 0.15
            
            var circle = Path()
            circle.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(circle, with: .color(Color(hue: hue, saturation: 1, brightness: 1).opacity(opacity)), lineWidth: 3 * (1 - ripplePhase))
        }
    }
    
    // MARK: - Effect 3: Fire
    private func drawFire(context: GraphicsContext, size: CGSize, state: EffectState) {
        let gradient = Gradient(colors: [
            Color.black.opacity(0.8),
            Color.red.opacity(0.8),
            Color.orange.opacity(0.9),
            Color.yellow.opacity(0.8)
        ])
        
        let flicker = 0.6 + 0.4 * sin(state.phase * .pi * 6 + Double(state.bassLevel) * 2)
        
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height * CGFloat(flicker))
            )
        )
    }
    
    // MARK: - Effect 4: Plasma
    private func drawPlasma(context: GraphicsContext, size: CGSize, state: EffectState) {
        let gridSize = 8
        let cellW = size.width / CGFloat(gridSize)
        let cellH = size.height / CGFloat(gridSize)
        let time = Float(state.frameCount) * 0.1
        
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let v1 = sin(Float(x) * 0.5 + time)
                let v2 = sin(Float(y) * 0.4 + time * 0.7)
                let v3 = sin((Float(x) + Float(y)) * 0.3 + time * 0.5)
                let v4 = sin(sqrt(Float(x * x + y * y)) * 0.4 - time)
                let value = ((v1 + v2 + v3 + v4) / 4.0 + 1.0) / 2.0
                
                let hue = Double((value * 360 + Float(state.frameCount * 2)).truncatingRemainder(dividingBy: 360)) / 360.0
                let color = Color(hue: hue, saturation: 1, brightness: Double(value * 0.5 + 0.5))
                
                let rect = CGRect(x: CGFloat(x) * cellW, y: CGFloat(y) * cellH, width: cellW, height: cellH)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
    
    // MARK: - Effect 5: Matrix Rain
    private func drawMatrixRain(context: GraphicsContext, size: CGSize, state: EffectState) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.3)))
        
        let cols = 16
        let colW = size.width / CGFloat(cols)
        
        for x in 0..<cols {
            let dropY = (state.phase * 2 + Double(x) * 0.1).truncatingRemainder(dividingBy: 1.0)
            let y = size.height * CGFloat(dropY)
            let trailLength = 5
            
            for i in 0..<trailLength {
                let ty = y - CGFloat(i) * (size.height / 16)
                if ty >= 0 && ty < size.height {
                    let brightness = 1.0 - Double(i) / Double(trailLength)
                    let color = i == 0 ? Color(red: 0.8, green: 1, blue: 0.8) : Color.green.opacity(brightness)
                    let rect = CGRect(x: CGFloat(x) * colW, y: ty, width: colW - 1, height: size.height / 16)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
    
    // MARK: - Effect 6: VU Meter
    private func drawVuMeter(context: GraphicsContext, size: CGSize, state: EffectState) {
        let level = CGFloat((state.bassLevel * 0.6 + state.midLevel * 0.3 + state.highLevel * 0.1) * 2)
        
        // Left bar
        let leftW = size.width * 0.4
        for y in 0..<16 {
            let yPos = size.height - CGFloat(y + 1) * size.height / 16
            if y < Int(level * 16) {
                let hue = (0.33 - Double(y) * 0.02).clamped(to: 0...0.33)
                context.fill(Path(CGRect(x: 0, y: yPos, width: leftW, height: size.height / 16)), with: .color(Color(hue: hue, saturation: 1, brightness: 1)))
            }
        }
        
        // Right bar
        let rightX = size.width * 0.6
        let rightLevel = level * CGFloat(0.9 + 0.2 * sin(Double(state.frameCount) * 0.1))
        for y in 0..<16 {
            let yPos = size.height - CGFloat(y + 1) * size.height / 16
            if y < Int(rightLevel * 16) {
                let hue = (0.33 - Double(y) * 0.02).clamped(to: 0...0.33)
                context.fill(Path(CGRect(x: rightX, y: yPos, width: size.width - rightX, height: size.height / 16)), with: .color(Color(hue: hue, saturation: 1, brightness: 1)))
            }
        }
        
        // Center
        let hue = Double(state.frameCount % 360) / 360.0
        context.fill(Path(CGRect(x: leftW, y: 0, width: rightX - leftW, height: size.height)), with: .color(Color(hue: hue, saturation: 1, brightness: 0.5).opacity(0.6)))
    }
    
    // MARK: - Effect 7: Starfield
    private func drawStarfield(context: GraphicsContext, size: CGSize, state: EffectState) {
        // Dark blue background
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hue: 0.61, saturation: 1, brightness: 0.1)))
        
        // Stars
        for i in 0..<40 {
            let x = CGFloat((i * 37) % 100) / 100.0 * size.width
            let y = CGFloat((i * 53) % 100) / 100.0 * size.height
            let brightness = 0.3 + 0.7 * sin(state.phase * .pi * 4 + Double(i) * 0.3)
            
            var star = Path()
            star.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
            context.fill(star, with: .color(Color.white.opacity(brightness)))
        }
    }
    
    // MARK: - Effect 8: Wave
    private func drawWave(context: GraphicsContext, size: CGSize, state: EffectState) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.4)))
        
        let t = Double(state.frameCount) * 0.1
        let amp1 = CGFloat(3 + state.bassLevel * 4)
        let amp2 = CGFloat(2 + state.midLevel * 3)
        let amp3 = CGFloat(1 + state.highLevel * 2)
        
        for x in stride(from: 0, to: size.width, by: 3) {
            let xNorm = Double(x) / Double(size.width)
            let y1 = size.height / 2 + amp1 * size.height / 16 * CGFloat(sin(xNorm * 4 * .pi + t))
            let y2 = size.height / 2 + amp2 * size.height / 16 * CGFloat(sin(xNorm * 6 * .pi + t + 1))
            let y3 = size.height / 2 + amp3 * size.height / 16 * CGFloat(sin(xNorm * 8 * .pi + t + 2))
            
            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y1 - 2, width: 4, height: 4)), with: .color(.red))
            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y2 - 2, width: 4, height: 4)), with: .color(.green))
            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y3 - 2, width: 4, height: 4)), with: .color(.blue))
        }
    }
    
    // MARK: - Effect 9: Fireworks
    private func drawFireworks(context: GraphicsContext, size: CGSize, state: EffectState) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.3)))
        
        let cx = size.width * (0.3 + CGFloat(state.frameCount % 100) / 200.0)
        let cy = size.height * 0.3
        let explosionPhase = state.phase
        
        for i in 0..<20 {
            let angle = Double(i) / 20.0 * .pi * 2
            let distance = CGFloat(explosionPhase) * size.height * 0.4
            let x = cx + distance * CGFloat(cos(angle))
            let y = cy + distance * CGFloat(sin(angle)) + distance * 0.5 // gravity
            let opacity = 1.0 - explosionPhase
            let hue = Double(state.frameCount % 60) / 60.0
            
            if opacity > 0 {
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                             with: .color(Color(hue: hue, saturation: 1, brightness: 1).opacity(opacity)))
            }
        }
    }
    
    // MARK: - Effect 10: Rainbow Wave
    private func drawRainbowWave(context: GraphicsContext, size: CGSize, state: EffectState) {
        let bands = 7
        let bandH = size.height / CGFloat(bands)
        let baseHue = Double(state.frameCount % 360) / 360.0
        
        for i in 0..<bands {
            let hue = (baseHue + Double(i) * 0.14).truncatingRemainder(dividingBy: 1.0)
            let wave = sin(Double(state.frameCount) * 0.1 + Double(i) * 0.5) * 10
            let brightness = 0.5 + Double(state.bassLevel) * 0.5
            let y = CGFloat(i) * bandH + CGFloat(wave)
            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: bandH)), with: .color(Color(hue: hue, saturation: 1, brightness: brightness)))
        }
    }
    
    // MARK: - Effect 11: Particle Burst
    private func drawParticleBurst(context: GraphicsContext, size: CGSize, state: EffectState) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) * 0.4
        
        for i in 0..<30 {
            let angle = Double(i) / 30.0 * .pi * 2 + state.phase * .pi * 2
            let distance = maxRadius * CGFloat(state.phase) * CGFloat(0.5 + sin(angle * 3) * 0.5)
            let x = center.x + distance * CGFloat(cos(angle))
            let y = center.y + distance * CGFloat(sin(angle))
            let hue = Double(i) / 30.0
            let opacity = 1.0 - state.phase
            
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                         with: .color(Color(hue: hue, saturation: 1, brightness: 1).opacity(opacity)))
        }
    }
    
    // MARK: - Effect 12: Kaleidoscope
    private func drawKaleidoscope(context: GraphicsContext, size: CGSize, state: EffectState) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let segments = 8
        
        for seg in 0..<segments {
            let angle = Double(seg) / Double(segments) * .pi * 2 + state.phase * .pi * 2
            let hue = (Double(seg) / Double(segments) + state.phase).truncatingRemainder(dividingBy: 1.0)
            
            var triangle = Path()
            triangle.move(to: center)
            let r = min(size.width, size.height) * 0.4
            triangle.addLine(to: CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle))))
            triangle.addLine(to: CGPoint(x: center.x + r * CGFloat(cos(angle + .pi * 2 / Double(segments))), y: center.y + r * CGFloat(sin(angle + .pi * 2 / Double(segments)))))
            triangle.closeSubpath()
            
            context.fill(triangle, with: .color(Color(hue: hue, saturation: 0.8, brightness: 0.9)))
        }
    }
    
    // MARK: - Effect 13: Frequency Spiral
    private func drawFrequencySpiral(context: GraphicsContext, size: CGSize, state: EffectState) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) * 0.45
        
        for i in 0..<60 {
            let t = Double(i) / 60.0
            let angle = t * .pi * 6 + state.phase * .pi * 4
            let radius = maxRadius * CGFloat(t)
            let x = center.x + radius * CGFloat(cos(angle))
            let y = center.y + radius * CGFloat(sin(angle))
            let hue = (t + state.phase).truncatingRemainder(dividingBy: 1.0)
            let pointSize = CGFloat(2 + 4 * t)
            
            context.fill(Path(ellipseIn: CGRect(x: x - pointSize/2, y: y - pointSize/2, width: pointSize, height: pointSize)),
                         with: .color(Color(hue: hue, saturation: 1, brightness: 1)))
        }
    }
    
    // MARK: - Effect 14: Bass Reactor
    private func drawBassReactor(context: GraphicsContext, size: CGSize, state: EffectState) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) * 0.4
        let pulse = CGFloat(0.7 + 0.3 * sin(state.phase * .pi * 4))
        
        for i in (0..<5).reversed() {
            let radius = maxRadius * CGFloat(Double(i + 1) / 5.0) * pulse
            let hue = 0.75 + Double(i) * 0.05 // Purple range
            let opacity = 1.0 - Double(i) * 0.15
            
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(Color(hue: hue, saturation: 0.8, brightness: 0.9).opacity(opacity)))
        }
    }
    
    // MARK: - Effect 15: Meteor Shower
    private func drawMeteorShower(context: GraphicsContext, size: CGSize, state: EffectState) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hue: 0.7, saturation: 0.8, brightness: 0.1)))
        
        for i in 0..<8 {
            let startX = CGFloat((i * 47 + state.frameCount * 3) % Int(size.width))
            let startY = CGFloat((i * 31) % Int(size.height / 2))
            let progress = (state.phase + Double(i) * 0.125).truncatingRemainder(dividingBy: 1.0)
            
            let x = startX + CGFloat(progress) * size.width * 0.3
            let y = startY + CGFloat(progress) * size.height * 0.7
            
            // Tail
            for t in 0..<10 {
                let tailX = x - CGFloat(t) * 8
                let tailY = y - CGFloat(t) * 6
                let opacity = 1.0 - Double(t) / 10.0
                context.fill(Path(ellipseIn: CGRect(x: tailX - 2, y: tailY - 2, width: 4, height: 4)),
                             with: .color(Color.white.opacity(opacity * (1 - progress))))
            }
        }
    }
    
    // MARK: - Effect 16: Breathing
    private func drawBreathing(context: GraphicsContext, size: CGSize, state: EffectState) {
        let breathe = 0.3 + 0.7 * sin(state.phase * .pi * 2)
        let hue = Double(state.frameCount % 360) / 360.0
        
        let gradient = Gradient(colors: [
            Color(hue: hue, saturation: 0.6, brightness: breathe),
            Color(hue: hue + 0.05, saturation: 0.5, brightness: breathe * 0.5),
            Color.black
        ])
        
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(gradient, center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0, endRadius: size.height * 0.8)
        )
    }
    
    // MARK: - Effect 17: DNA Helix
    private func drawDnaHelix(context: GraphicsContext, size: CGSize, state: EffectState) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.4)))
        
        let cx = size.width / 2
        let amplitude = size.width * 0.3
        
        for y in stride(from: 0, to: size.height, by: 8) {
            let yNorm = Double(y) / Double(size.height)
            let phase1 = yNorm * .pi * 4 + state.phase * .pi * 4
            let phase2 = phase1 + .pi
            
            let x1 = cx + amplitude * CGFloat(sin(phase1))
            let x2 = cx + amplitude * CGFloat(sin(phase2))
            
            // Strand 1
            context.fill(Path(ellipseIn: CGRect(x: x1 - 4, y: y - 4, width: 8, height: 8)), with: .color(.cyan))
            // Strand 2
            context.fill(Path(ellipseIn: CGRect(x: x2 - 4, y: y - 4, width: 8, height: 8)), with: .color(Color(hue: 0.83, saturation: 1, brightness: 1)))
            
            // Connection
            if Int(y) % 24 == 0 {
                var line = Path()
                line.move(to: CGPoint(x: x1, y: y))
                line.addLine(to: CGPoint(x: x2, y: y))
                context.stroke(line, with: .color(Color.white.opacity(0.3)), lineWidth: 2)
            }
        }
    }
    
    // MARK: - Effect 18: Audio Scope
    private func drawAudioScope(context: GraphicsContext, size: CGSize, state: EffectState) {
        // Grid background
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hue: 0.3, saturation: 0.8, brightness: 0.1)))
        
        // Waveform
        var path = Path()
        let midY = size.height / 2
        
        for x in stride(from: 0, to: size.width, by: 2) {
            let xNorm = Double(x) / Double(size.width)
            let amp = CGFloat(state.bassLevel * 0.3 + state.midLevel * 0.2) * size.height
            let y = midY + amp * CGFloat(sin(xNorm * .pi * 8 + state.phase * .pi * 4))
            
            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        context.stroke(path, with: .color(.green), lineWidth: 2)
    }
    
    // MARK: - Effect 19: Bouncing Balls
    private func drawBouncingBalls(context: GraphicsContext, size: CGSize, state: EffectState) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.4)))
        
        for i in 0..<5 {
            let t = (state.phase + Double(i) * 0.2).truncatingRemainder(dividingBy: 1.0)
            let bounceY = abs(sin(t * .pi * 2)) // Bounce motion
            let x = size.width * CGFloat(0.1 + Double(i) * 0.2)
            let y = size.height - size.height * 0.7 * CGFloat(bounceY) - 20
            let hue = Double(i) / 5.0
            let radius: CGFloat = 15
            
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(Color(hue: hue, saturation: 0.8, brightness: 0.9)))
        }
    }
    
    // MARK: - Effect 20: Lava Lamp
    private func drawLavaLamp(context: GraphicsContext, size: CGSize, state: EffectState) {
        // Warm background
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hue: 0.05, saturation: 0.6, brightness: 0.2)))
        
        // Blobs
        for i in 0..<4 {
            let t = (state.phase + Double(i) * 0.25).truncatingRemainder(dividingBy: 1.0)
            let x = size.width * CGFloat(0.2 + sin(t * .pi * 2 + Double(i)) * 0.3)
            let y = size.height * CGFloat(0.2 + t * 0.6)
            let radius = size.width * CGFloat(0.1 + 0.05 * sin(t * .pi * 4))
            let hue = 0.05 + Double(i) * 0.03
            
            let blobGradient = Gradient(colors: [Color(hue: hue, saturation: 0.8, brightness: 0.9), Color(hue: hue, saturation: 0.8, brightness: 0.5).opacity(0.5)])
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .radialGradient(blobGradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
        }
    }
    
    // MARK: - Effect 21: Ambient
    private func drawAmbient(context: GraphicsContext, size: CGSize, state: EffectState) {
        let gradient = Gradient(colors: [
            Color(hue: 0.15, saturation: 0.5, brightness: 0.4),
            Color(hue: 0.12, saturation: 0.6, brightness: 0.25),
            Color.black.opacity(0.9)
        ])
        
        let pulseOffset = 0.05 * sin(state.phase * .pi * 2)
        
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                gradient,
                center: CGPoint(x: size.width / 2, y: size.height * CGFloat(0.7 + pulseOffset)),
                startRadius: 0,
                endRadius: size.height
            )
        )
    }
    
    // MARK: - Effect 255: Off
    private func drawOff(context: GraphicsContext, size: CGSize) {
        let gradient = Gradient(colors: [Color(hex: "1a1a2e"), Color.black])
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }
    
    // MARK: - Default Gradient
    private func drawDefaultGradient(context: GraphicsContext, size: CGSize, state: EffectState) {
        let hue = (Double(effectId) * 0.05 + state.phase * 0.1).truncatingRemainder(dividingBy: 1.0)
        let gradient = Gradient(colors: [
            Color(hue: hue, saturation: 0.6, brightness: 0.5),
            Color(hue: hue + 0.1, saturation: 0.5, brightness: 0.3),
            Color.black.opacity(0.8)
        ])
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(gradient, center: CGPoint(x: size.width / 2, y: size.height * 0.6), startRadius: 0, endRadius: size.height))
    }
}

// Helper extension for clamping
private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
