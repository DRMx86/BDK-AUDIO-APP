import Foundation
import AVFoundation
import AudioToolbox

/// Converts audio files to WAV format optimized for ESP32 playback.
/// Output format: 16-bit PCM, mono, dynamically adjusted sample rate to fit 200KB limit.
/// Matches Android AudioConverter.kt behavior exactly.
enum AudioConverter {
    
    // MARK: - Constants
    
    private static let preferredSampleRate: Double = 22050  // Good quality default
    private static let minSampleRate: Double = 8000         // Minimum acceptable quality
    private static let targetChannels: UInt32 = 1           // Mono
    private static let targetBitsPerSample: UInt32 = 16
    
    private static let maxOutputSize = 200 * 1024           // 200KB max file size
    private static let maxAudioData = maxOutputSize - 44    // Minus WAV header
    
    // MARK: - Result Type
    
    enum ConversionError: Error, LocalizedError {
        case fileNotAccessible
        case noAudioTrack
        case conversionFailed(String)
        case fileTooLarge
        case invalidFormat
        
        var errorDescription: String? {
            switch self {
            case .fileNotAccessible:
                return "Cannot access audio file"
            case .noAudioTrack:
                return "No audio track found"
            case .conversionFailed(let reason):
                return "Conversion failed: \(reason)"
            case .fileTooLarge:
                return "Audio too long for upload"
            case .invalidFormat:
                return "Invalid audio format"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Convert any supported audio file to WAV format.
    /// Returns the WAV data ready for upload, or an error.
    static func convertToWav(url: URL) -> Result<Data, ConversionError> {
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            return .failure(.fileNotAccessible)
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            // Read and decode audio file
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = UInt32(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return .failure(.conversionFailed("Cannot create buffer"))
            }
            
            try audioFile.read(into: buffer)
            
            // Convert to mono Float32 first
            let monoData = convertToMono(buffer: buffer)
            
            // Find optimal sample rate to fit within size limit
            let (resampledData, usedSampleRate) = resampleToFit(
                samples: monoData,
                inputSampleRate: format.sampleRate
            )
            
            // Create WAV file
            let wavData = createWavFile(samples: resampledData, sampleRate: usedSampleRate)
            
            print("AudioConverter: Converted to \(wavData.count) bytes WAV at \(Int(usedSampleRate))Hz")
            
            return .success(wavData)
            
        } catch {
            return .failure(.conversionFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Private Helpers
    
    /// Convert stereo/multi-channel to mono
    private static func convertToMono(buffer: AVAudioPCMBuffer) -> [Float] {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        
        var monoSamples = [Float](repeating: 0, count: frameLength)
        
        if channelCount == 1 {
            // Already mono
            for i in 0..<frameLength {
                monoSamples[i] = channelData[0][i]
            }
        } else {
            // Mix down to mono
            for i in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        }
        
        return monoSamples
    }
    
    /// Resample to fit within max size, trying preferred sample rate first
    private static func resampleToFit(samples: [Float], inputSampleRate: Double) -> ([Int16], Double) {
        // Calculate duration
        let duration = Double(samples.count) / inputSampleRate
        
        // Try sample rates from preferred down to minimum
        let sampleRatesToTry: [Double] = [22050, 16000, 11025, 8000]
        
        for targetRate in sampleRatesToTry {
            let expectedSamples = Int(duration * targetRate)
            let expectedBytes = expectedSamples * 2 // 16-bit = 2 bytes per sample
            
            if expectedBytes <= maxAudioData {
                // This sample rate fits, use it
                let resampled = resample(samples: samples, from: inputSampleRate, to: targetRate)
                return (resampled, targetRate)
            }
        }
        
        // Audio is too long even at minimum sample rate
        // Truncate to fit
        let targetRate = minSampleRate
        let maxSamples = maxAudioData / 2
        var resampled = resample(samples: samples, from: inputSampleRate, to: targetRate)
        
        if resampled.count > maxSamples {
            resampled = Array(resampled.prefix(maxSamples))
        }
        
        return (resampled, targetRate)
    }
    
    /// Simple linear resampling from one rate to another
    private static func resample(samples: [Float], from inputRate: Double, to outputRate: Double) -> [Int16] {
        let ratio = inputRate / outputRate
        let outputLength = Int(Double(samples.count) / ratio)
        
        var output = [Int16](repeating: 0, count: outputLength)
        
        for i in 0..<outputLength {
            let srcIndex = Double(i) * ratio
            let srcIndexInt = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexInt))
            
            // Linear interpolation
            let sample1 = samples[min(srcIndexInt, samples.count - 1)]
            let sample2 = samples[min(srcIndexInt + 1, samples.count - 1)]
            let interpolated = sample1 + (sample2 - sample1) * fraction
            
            // Convert to Int16 (clamp to prevent overflow)
            let scaled = interpolated * 32767.0
            output[i] = Int16(max(-32768, min(32767, scaled)))
        }
        
        return output
    }
    
    /// Create WAV file with proper header
    private static func createWavFile(samples: [Int16], sampleRate: Double) -> Data {
        var data = Data()
        
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = dataSize + 36
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // Subchunk1Size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // AudioFormat (PCM)
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Audio data (little-endian Int16)
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        
        return data
    }
}
