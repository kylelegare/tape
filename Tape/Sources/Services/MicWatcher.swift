import AVFoundation
import CoreAudio
import Foundation

/// Watches for mic usage via CoreAudio property listeners (event-driven, not polling).
/// Uses kAudioDevicePropertyDeviceIsRunningSomewhere — fires immediately when
/// any app starts or stops using the microphone.
final class MicWatcher {
    var onMicGrabbed: (() -> Void)?
    var onMicReleased: (() -> Void)?

    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var isRunning = false
    private var listenerInstalled = false

    func start() {
        // Request mic permission first
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            installListener()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.installListener() }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        removeListener()
    }

    private func installListener() {
        // Get the default input device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            NSLog("[Tape] Could not get default input device: \(status)")
            return
        }

        self.deviceID = deviceID
        NSLog("[Tape] Default input device ID: \(deviceID)")

        // Listen for kAudioDevicePropertyDeviceIsRunningSomewhere changes
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = AudioObjectAddPropertyListener(
            deviceID,
            &runningAddress,
            micPropertyListener,
            selfPtr
        )

        if result == noErr {
            listenerInstalled = true
            NSLog("[Tape] Mic listener installed successfully")
            // Check initial state
            checkMicState()
        } else {
            NSLog("[Tape] Failed to install mic listener: \(result)")
        }
    }

    private func removeListener() {
        guard listenerInstalled, deviceID != kAudioObjectUnknown else { return }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(deviceID, &runningAddress, micPropertyListener, selfPtr)
        listenerInstalled = false
    }

    fileprivate func checkMicState() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunningSomewhere: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunningSomewhere)
        guard status == noErr else { return }

        let nowRunning = isRunningSomewhere != 0

        if nowRunning && !isRunning {
            NSLog("[Tape] Mic grabbed by another app!")
            isRunning = true
            DispatchQueue.main.async { self.onMicGrabbed?() }
        } else if !nowRunning && isRunning {
            NSLog("[Tape] Mic released!")
            isRunning = false
            DispatchQueue.main.async { self.onMicReleased?() }
        }
    }
}

/// CoreAudio property listener callback (C function)
private func micPropertyListener(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let watcher = Unmanaged<MicWatcher>.fromOpaque(clientData).takeUnretainedValue()
    watcher.checkMicState()
    return noErr
}
