import SwiftUI
import sharedKit
import CommonCrypto

// MARK: - OTA Header View
struct OtaHeaderView: View {
    let title: String
    let isUploading: Bool
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: {
                if !isUploading { onBack() }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44) // nice tap target
            }
            .disabled(isUploading)

            Spacer()

            Text(title)
                .font(.title3.bold())
                .foregroundColor(.white)

            Spacer()

            // Keeps title centered
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .padding(.top, 6)
        // Optional: subtle background behind the header
        .background(Color.black.opacity(0.001)) // keep it "hit-test solid" without changing look
    }
}

// MARK: - OTA View
struct OtaView: View {
    @ObservedObject var viewModel: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss

    // OTA State
    @State private var currentVersion: String = ""
    @State private var latestVersion: String = ""
    @State private var statusText: String = "Ready - Check for updates"
    @State private var downloadProgress: Double = 0
    @State private var uploadProgress: Double = 0
    @State private var isCheckingUpdates = false
    @State private var isDownloading = false
    @State private var isUploading = false
    @State private var firmwareData: Data? = nil
    @State private var updateAvailable = false

    // OTA Downloader
    private let otaDownloader = OtaDownloader()

    var body: some View {
        ZStack {
            // Background (can ignore safe area safely)
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(hexString: "1a1a2e")]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Main content (NO header in here)
            VStack(spacing: 16) {
                // Version info card
                VStack(spacing: 16) {
                    // Current version
                    VStack(spacing: 4) {
                        Text("CURRENT VERSION")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .tracking(2)

                        Text(currentVersion.isEmpty ? viewModel.firmwareVersion : currentVersion)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }

                    // Latest version (if available)
                    if !latestVersion.isEmpty {
                        VStack(spacing: 4) {
                            Text("AVAILABLE VERSION")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .tracking(2)

                            Text(latestVersion)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)

                // Status text
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.cyan)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Progress bars
                if isDownloading {
                    VStack(spacing: 8) {
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.gray)
                        ProgressView(value: downloadProgress)
                            .tint(.cyan)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    .padding(.horizontal)
                }

                if isUploading {
                    VStack(spacing: 8) {
                        Text("Uploading to device...")
                            .font(.caption)
                            .foregroundColor(.gray)
                        ProgressView(value: uploadProgress)
                            .tint(.green)
                        Text("\(Int(uploadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: checkForUpdates) {
                        HStack {
                            if isCheckingUpdates {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Check for Updates")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    .disabled(isCheckingUpdates || isDownloading || isUploading)

                    if updateAvailable {
                        Button(action: startUpdate) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download & Install")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                        .disabled(isDownloading || isUploading)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        // ✅ This is the key fix: header is inserted into the TOP safe area.
        // It will sit right under the iPhone status bar (not floating lower).
        .safeAreaInset(edge: .top, spacing: 0) {
            OtaHeaderView(
                title: "Firmware Update",
                isUploading: isUploading,
                onBack: { dismiss() }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }

        // If this screen is inside a NavigationStack, hide the system nav bar
        // so it doesn't reserve extra space / conflict with your custom header.
        .toolbar(.hidden, for: .navigationBar)

        .onAppear {
            currentVersion = viewModel.firmwareVersion
        }
        .interactiveDismissDisabled(isUploading)
    }

    // MARK: - Check for Updates
    private func checkForUpdates() {
        isCheckingUpdates = true
        statusText = "Checking for updates..."

        Task {
            do {
                let info = try await otaDownloader.checkForUpdates(currentVersion: currentVersion)

                await MainActor.run {
                    isCheckingUpdates = false

                    if let info = info {
                        latestVersion = info.version
                        updateAvailable = true
                        statusText = "Update available!"
                    } else {
                        // If you want to HIDE the "available version" section when up-to-date,
                        // set latestVersion = "" instead of currentVersion.
                        latestVersion = ""
                        updateAvailable = false
                        statusText = "You have the latest version"
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingUpdates = false
                    statusText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Start Update
    private func startUpdate() {
        guard updateAvailable else { return }

        isDownloading = true
        downloadProgress = 0
        statusText = "Downloading firmware..."

        Task {
            do {
                // Get firmware info again for file ID
                guard let info = try await otaDownloader.checkForUpdates(currentVersion: "0.0.0") else {
                    throw NSError(domain: "OTA", code: 1, userInfo: [NSLocalizedDescriptionKey: "No firmware found"])
                }

                let data = try await otaDownloader.downloadFirmware(
                    info: info,
                    onProgress: { progress in
                        Task { @MainActor in
                            downloadProgress = Double(progress) / 100.0
                        }
                    }
                )

                await MainActor.run {
                    isDownloading = false
                    firmwareData = data
                    statusText = "Download complete. Starting upload..."
                }

                startFirmwareUpload()

            } catch {
                await MainActor.run {
                    isDownloading = false
                    statusText = "Download failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Firmware Upload
    private func startFirmwareUpload() {
        guard let firmware = firmwareData else {
            statusText = "No firmware data"
            return
        }

        isUploading = true
        uploadProgress = 0
        statusText = "Uploading firmware (\(firmware.count / 1024) KB)..."

        viewModel.uploadFirmware(
            data: firmware,
            onProgress: { progress in
                DispatchQueue.main.async {
                    uploadProgress = Double(progress) / 100.0
                }
            },
            onComplete: { success in
                DispatchQueue.main.async {
                    isUploading = false
                    if success {
                        statusText = "Update complete! Device will restart."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            dismiss()
                        }
                    } else {
                        statusText = "Upload failed. Please try again."
                    }
                }
            }
        )
    }
}

// MARK: - OTA Downloader
class OtaDownloader {

    // Google Drive file ID for latest.txt
    private let gdriveLatestTxtId = "1fHQ4qn4enJ5hXY0BJX1fTKX09guNOb2y"

    // AES-256 Key
    private let aesKey: [UInt8] = [
        0x5A, 0x2B, 0x9C, 0x4E,
        0x1F, 0x8D, 0x6A, 0x3C,
        0x7B, 0x0E, 0x4F, 0x2D,
        0x8C, 0x5A, 0x1B, 0x9E,
        0x3D, 0x6C, 0x0F, 0x4A,
        0x7E, 0x2B, 0x8D, 0x5C,
        0x1A, 0x9F, 0x3E, 0x6B,
        0x0D, 0x4C, 0x7A, 0x2E
    ]

    struct FirmwareInfo {
        let version: String
        let fileId: String
    }

    func checkForUpdates(currentVersion: String) async throws -> FirmwareInfo? {
        let latestTxtUrl = "https://drive.google.com/uc?export=download&id=\(gdriveLatestTxtId)"

        guard let url = URL(string: latestTxtUrl) else {
            throw NSError(domain: "OTA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "OTA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Parse: VERSION,FILE_ID
        let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard parts.count == 2 else {
            throw NSError(domain: "OTA", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid latest.txt format"])
        }

        let availableVersion = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let firmwareFileId = String(parts[1]).trimmingCharacters(in: .whitespaces)

        if isNewerVersion(availableVersion, than: currentVersion) {
            return FirmwareInfo(version: availableVersion, fileId: firmwareFileId)
        }

        return nil
    }

    func downloadFirmware(info: FirmwareInfo, onProgress: @escaping (Int) -> Void) async throws -> Data {
        let downloadUrl = "https://drive.google.com/uc?export=download&id=\(info.fileId)"

        guard let url = URL(string: downloadUrl) else {
            throw NSError(domain: "OTA", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        let contentLength = response.expectedContentLength
        var encryptedData = Data()
        var downloadedBytes: Int64 = 0

        for try await byte in asyncBytes {
            encryptedData.append(byte)
            downloadedBytes += 1

            if contentLength > 0 {
                let progress = Int((downloadedBytes * 100) / contentLength)
                onProgress(progress)
            }
        }

        return try decryptFirmware(encryptedData)
    }

    private func decryptFirmware(_ encryptedData: Data) throws -> Data {
        guard encryptedData.count > kCCBlockSizeAES128 else {
            throw NSError(domain: "OTA", code: 5, userInfo: [NSLocalizedDescriptionKey: "Encrypted data too short"])
        }

        let iv = encryptedData.prefix(kCCBlockSizeAES128)
        let ciphertext = encryptedData.dropFirst(kCCBlockSizeAES128)

        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var decryptedData = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status: CCCryptorStatus = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                iv.withUnsafeBytes { ivBytes in
                    aesKey.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            kCCKeySizeAES256,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress,
                            ciphertext.count,
                            decryptedBytes.baseAddress,
                            bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw NSError(domain: "OTA", code: 6, userInfo: [NSLocalizedDescriptionKey: "Decryption failed: \(status)"])
        }

        return decryptedData.prefix(numBytesDecrypted)
    }

    private func isNewerVersion(_ available: String, than current: String) -> Bool {
        let availableParts = available.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(availableParts.count, currentParts.count) {
            let a = i < availableParts.count ? availableParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0

            if a > c { return true }
            if a < c { return false }
        }

        return false
    }
}

extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Previews
struct OtaView_Previews: PreviewProvider {
    static var previews: some View {
        OtaView(viewModel: ConnectionViewModel())
    }
}
