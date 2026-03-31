import AudioToolbox
import AVFoundation
import Foundation

/// Records system audio via CoreAudio process tap + microphone via AVAudioEngine.
/// Requires NSAudioCaptureUsageDescription (system audio) and NSMicrophoneUsageDescription (mic).
/// No Screen Recording permission needed.
final class AudioRecorder {
    private(set) var isRecording = false

    // MARK: - System Audio (CoreAudio Process Tap)

    private var processTapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var systemFile: AVAudioFile?
    private var systemFormat: AVAudioFormat?
    private let tapQueue = DispatchQueue(label: "com.tape.processtap", qos: .userInitiated)

    // MARK: - Microphone (AVAudioEngine)

    private var engine: AVAudioEngine?
    private var micFile: AVAudioFile?

    // MARK: - URLs

    private var systemTempURL: URL?
    private var micTempURL: URL?
    private var finalOutputURL: URL?

    // MARK: - Public API

    func startRecording() async throws -> URL {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        let tempDir = FileManager.default.temporaryDirectory
        let ts = Int(Date().timeIntervalSince1970)
        let sysURL = tempDir.appendingPathComponent("tape-sys-\(ts).caf")
        let micURL = tempDir.appendingPathComponent("tape-mic-\(ts).caf")
        let outURL = tempDir.appendingPathComponent("tape-\(ts).m4a")

        systemTempURL = sysURL
        micTempURL = micURL
        finalOutputURL = outURL

        // System audio capture — skip gracefully if no audio processes are running yet
        do {
            try setupProcessTap(outputURL: sysURL)
        } catch {
            // System audio unavailable (no processes or permission denied) — mic-only recording
            systemTempURL = nil
        }
        try setupMicCapture(outputURL: micURL)

        isRecording = true
        return outURL
    }

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false

        teardownProcessTap()
        teardownMicCapture()

        guard let micURL = micTempURL, let outURL = finalOutputURL else { return }

        if let sysURL = systemTempURL {
            // Mix system audio + mic
            try? await mixTracks(systemURL: sysURL, micURL: micURL, to: outURL)
            try? FileManager.default.removeItem(at: sysURL)
        } else {
            // Mic-only — just convert the CAF to m4a
            try? await convertToM4A(inputURL: micURL, outputURL: outURL)
        }

        try? FileManager.default.removeItem(at: micURL)
    }

    // MARK: - System Audio Capture

    private func setupProcessTap(outputURL: URL) throws {
        // Collect all active audio processes so we capture everything playing
        let processIDs = allAudioProcessIDs()

        let tapDesc = CATapDescription(stereoMixdownOfProcesses: processIDs)
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapErr = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard tapErr == noErr else { throw RecorderError.coreAudioError(tapErr) }
        processTapID = tapID

        let systemOutputID = try defaultSystemOutputDevice()
        let outputUID = try deviceUID(for: systemOutputID)

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "TapeCapture",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDesc.uuid.uuidString
            ]]
        ]

        var aggID = AudioObjectID(kAudioObjectUnknown)
        let aggErr = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard aggErr == noErr else { throw RecorderError.coreAudioError(aggErr) }
        aggregateDeviceID = aggID

        var streamDesc = try tapStreamFormat(for: tapID)
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else {
            throw RecorderError.invalidFormat
        }
        systemFormat = format

        let settings: [String: Any] = [
            AVFormatIDKey: streamDesc.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved
        )
        systemFile = file

        let ioErr = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggID, tapQueue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self, let file = self.systemFile, let fmt = self.systemFormat else { return }
            if let buf = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: inInputData, deallocator: nil) {
                try? file.write(from: buf)
            }
        }
        guard ioErr == noErr else { throw RecorderError.coreAudioError(ioErr) }

        let startErr = AudioDeviceStart(aggID, deviceProcID)
        guard startErr == noErr else { throw RecorderError.coreAudioError(startErr) }
    }

    private func teardownProcessTap() {
        systemFile = nil

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if let procID = deviceProcID {
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
                deviceProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = kAudioObjectUnknown
        }
    }

    // MARK: - Mic Capture

    private func setupMicCapture(outputURL: URL) throws {
        let eng = AVAudioEngine()
        let input = eng.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true
        ]
        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        micFile = file

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            try? self?.micFile?.write(from: buffer)
        }
        try eng.start()
        engine = eng
    }

    private func teardownMicCapture() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        micFile = nil
    }

    // MARK: - Mixing

    private func mixTracks(systemURL: URL, micURL: URL, to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let sysAsset = AVURLAsset(url: systemURL)
        let micAsset = AVURLAsset(url: micURL)

        let sysDuration = try await sysAsset.load(.duration)
        let micDuration = try await micAsset.load(.duration)
        let duration = CMTimeMaximum(sysDuration, micDuration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        if let sysTrack = try await sysAsset.loadTracks(withMediaType: .audio).first {
            let t = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try t?.insertTimeRange(timeRange, of: sysTrack, at: .zero)
        }
        if let micTrack = try await micAsset.loadTracks(withMediaType: .audio).first {
            let t = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try t?.insertTimeRange(timeRange, of: micTrack, at: .zero)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.exportFailed
        }
        try await exporter.export(to: outputURL, as: .m4a)
    }

    private func convertToM4A(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.exportFailed
        }
        try await exporter.export(to: outputURL, as: .m4a)
    }

    // MARK: - CoreAudio Helpers

    private func allAudioProcessIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        return ids.filter { $0 != kAudioObjectUnknown }
    }

    private func defaultSystemOutputDevice() throws -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard err == noErr else { throw RecorderError.coreAudioError(err) }
        return deviceID
    }

    private func deviceUID(for deviceID: AudioObjectID) throws -> String {
        var uid: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard err == noErr, let uid else { throw RecorderError.coreAudioError(err) }
        return uid.takeRetainedValue() as String
    }

    private func tapStreamFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var desc = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &desc)
        guard err == noErr else { throw RecorderError.coreAudioError(err) }
        return desc
    }
}

// MARK: - Errors

enum RecorderError: Error, LocalizedError {
    case alreadyRecording
    case invalidFormat
    case exportFailed
    case coreAudioError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "Already recording"
        case .invalidFormat: return "Invalid audio format from system tap"
        case .exportFailed: return "Failed to export mixed audio"
        case .coreAudioError(let code): return "CoreAudio error \(code)"
        }
    }
}
