import AudioToolbox
import AVFoundation
import Foundation

/// Polls kAudioDevicePropertyDeviceIsRunningSomewhere every second.
/// Re-queries the default input device on each tick so mic switches are handled automatically.
final class MicWatcher {
    var onMicGrabbed: (() -> Void)?
    var onMicReleased: (() -> Void)?

    private var timer: Timer?
    private var wasRunning = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startPolling()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.startPolling() } }
            }
        default:
            break
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startPolling() {
        // Check immediately, then every second
        checkState()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkState()
        }
    }

    private func checkState() {
        let isRunning = micIsRunningSomewhere()
            || (AVCaptureDevice.default(for: .audio)?.isInUseByAnotherApplication ?? false)
        if isRunning && !wasRunning {
            wasRunning = true
            onMicGrabbed?()
        } else if !isRunning && wasRunning {
            wasRunning = false
            onMicReleased?()
        }
    }

    /// Reads kAudioDevicePropertyDeviceIsRunningSomewhere from the current default input device.
    private func micIsRunningSomewhere() -> Bool {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var hwAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &hwAddress, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return false }

        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var devAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            deviceID, &devAddress, 0, nil, &runningSize, &isRunning
        ) == noErr else { return false }

        return isRunning != 0
    }
}
