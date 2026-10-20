import SwiftUI
import UniformTypeIdentifiers

// MARK: - Device Info Sheet (matching Android DeviceInfoBottomSheet exactly)

struct DeviceInfoSheet: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Sound upload state
    @State private var pendingSoundType: Int = -1
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var showFilePicker = false
    @State private var showDeleteConfirmation = false
    @State private var soundToDelete: Int = -1
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(hex: "1a1a2e")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Connection Status Card
                        DeviceInfoCardView(title: "CONNECTION") {
                            VStack(spacing: 12) {
                                InfoRow(label: "Device Name", value: viewModel.deviceName)
                                InfoRow(label: "Status", value: viewModel.isConnected ? "Connected" : "Disconnected", valueColor: viewModel.isConnected ? .green : .red)
                                InfoRow(label: "Firmware", value: viewModel.firmwareVersion)
                            }
                        }
                        
                        // Sound Management Card
                        DeviceInfoCardView(title: "SOUNDS") {
                            VStack(spacing: 16) {
                                // Mute toggle
                                HStack {
                                    Image(systemName: viewModel.soundMuted ? "speaker.slash.fill" : "speaker.fill")
                                        .foregroundColor(.cyan)
                                    Text("Mute Sounds")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Toggle("", isOn: $viewModel.soundMuted)
                                        .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                        .labelsHidden()
                                        .onChange(of: viewModel.soundMuted) { _, newValue in
                                            viewModel.sendSoundMute(newValue)
                                        }
                                }
                                
                                Divider().background(Color.gray.opacity(0.3))
                                
                                // Sound upload buttons
                                SoundUploadRow(
                                    title: "Startup Sound",
                                    hasSound: viewModel.soundStatus & 0x01 != 0,
                                    isUploading: isUploading && pendingSoundType == 0,
                                    progress: uploadProgress,
                                    onUpload: { startUpload(soundType: 0) },
                                    onDelete: { confirmDelete(soundType: 0) }
                                )
                                
                                SoundUploadRow(
                                    title: "Pairing Sound",
                                    hasSound: viewModel.soundStatus & 0x02 != 0,
                                    isUploading: isUploading && pendingSoundType == 1,
                                    progress: uploadProgress,
                                    onUpload: { startUpload(soundType: 1) },
                                    onDelete: { confirmDelete(soundType: 1) }
                                )
                                
                                SoundUploadRow(
                                    title: "Connected Sound",
                                    hasSound: viewModel.soundStatus & 0x04 != 0,
                                    isUploading: isUploading && pendingSoundType == 2,
                                    progress: uploadProgress,
                                    onUpload: { startUpload(soundType: 2) },
                                    onDelete: { confirmDelete(soundType: 2) }
                                )
                                
                                SoundUploadRow(
                                    title: "Max Volume Sound",
                                    hasSound: viewModel.soundStatus & 0x08 != 0,
                                    isUploading: isUploading && pendingSoundType == 3,
                                    progress: uploadProgress,
                                    onUpload: { startUpload(soundType: 3) },
                                    onDelete: { confirmDelete(soundType: 3) }
                                )
                                
                                Text("Tap to upload • Long press to delete")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Device Info")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            AudioFilePicker { url in
                if let url = url {
                    handleFileSelected(url)
                }
            }
        }
        .alert("Delete Sound", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.deleteSound(soundType: soundToDelete)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this sound?")
        }
    }
    
    private func startUpload(soundType: Int) {
        pendingSoundType = soundType
        showFilePicker = true
    }
    
    private func confirmDelete(soundType: Int) {
        soundToDelete = soundType
        showDeleteConfirmation = true
    }
    
    private func handleFileSelected(_ url: URL) {
        guard pendingSoundType >= 0 else { return }
        
        let soundType = pendingSoundType
        pendingSoundType = -1
        
        isUploading = true
        uploadProgress = 0
        self.pendingSoundType = soundType // Keep track for UI
        
        // Convert audio to WAV in background
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AudioConverter.convertToWav(url: url)
            
            DispatchQueue.main.async {
                switch result {
                case .success(let wavData):
                    // Start upload
                    viewModel.uploadSound(
                        soundType: soundType,
                        data: wavData,
                        onProgress: { progress in
                            self.uploadProgress = Double(progress) / 100.0
                        },
                        onComplete: { success in
                            self.isUploading = false
                            self.pendingSoundType = -1
                            if !success {
                                // Show error (could add alert)
                            }
                        }
                    )
                    
                case .failure(let error):
                    self.isUploading = false
                    self.pendingSoundType = -1
                    print("Audio conversion failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Device Info Card

struct DeviceInfoCardView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .tracking(2)
            
            content
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .cyan
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Sound Upload Row

struct SoundUploadRow: View {
    let title: String
    let hasSound: Bool
    let isUploading: Bool
    let progress: Double
    let onUpload: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(.white)
                
                if isUploading {
                    ProgressView(value: progress)
                        .tint(.cyan)
                } else {
                    Text(hasSound ? "Custom sound uploaded" : "Using default")
                        .font(.caption)
                        .foregroundColor(hasSound ? .green : .gray)
                }
            }
            
            Spacer()
            
            if !isUploading {
                Button(action: onUpload) {
                    Image(systemName: hasSound ? "arrow.up.circle.fill" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.cyan)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                        if hasSound {
                            onDelete()
                        }
                    }
                )
            } else {
                ProgressView()
                    .tint(.cyan)
            }
        }
    }
}

// MARK: - Audio File Picker

struct AudioFilePicker: UIViewControllerRepresentable {
    let onFileSelected: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [.audio, .mp3, .wav, .aiff]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFileSelected: onFileSelected)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFileSelected: (URL?) -> Void
        
        init(onFileSelected: @escaping (URL?) -> Void) {
            self.onFileSelected = onFileSelected
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFileSelected(urls.first)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFileSelected(nil)
        }
    }
}

// MARK: - Previews

struct DeviceInfoSheet_Previews: PreviewProvider {
    static var previews: some View {
        DeviceInfoSheet(viewModel: ConnectionViewModel())
    }
}
