import AppKit
import AVFoundation
import CoreAudio
import Foundation

/// Watches for mic usage at the process level using CoreAudio's process object API
/// (macOS 14+). Fires onMicGrabbed/onMicReleased only when a bundle ID on the
/// allowlist starts or stops capturing microphone input.
///
/// Two-tier approach:
///   1. System listener on kAudioHardwarePropertyProcessObjectList fires when any
///      process joins or leaves CoreAudio.
///   2. Per-process listener on kAudioProcessPropertyIsRunningInput fires when a
///      specific process starts or stops capturing.
///
/// Requires a signed build — macOS Sequoia privacy APIs return incorrect state
/// for unsigned debug builds.
final class MicWatcher {
    var onMicGrabbed: (() -> Void)?
    var onMicReleased: (() -> Void)?

    /// Weak reference so MicAllowlist is owned by RecordingManager.
    weak var allowlist: MicAllowlist?

    private var processListBlock: AudioObjectPropertyListenerBlock?
    private var perProcessBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var activeMeetingPIDs: Set<pid_t> = []

    // MARK: - Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            installListeners()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.installListeners() }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        removeAllListeners()
    }

    /// Re-evaluates trigger state after the allowlist changes.
    func reevaluate() {
        reevaluateTriggerState()
    }

    // MARK: - Listener installation

    private func installListeners() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshPerProcessListeners()
                self?.reevaluateTriggerState()
            }
        }
        processListBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block
        )

        // Seed with the current process list.
        refreshPerProcessListeners()
        reevaluateTriggerState()
    }

    private func removeAllListeners() {
        if let block = processListBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                nil,
                block
            )
            processListBlock = nil
        }

        for (objectID, block) in perProcessBlocks {
            removeIsRunningInputListener(objectID: objectID, block: block)
        }
        perProcessBlocks.removeAll()
        activeMeetingPIDs.removeAll()
    }

    // MARK: - Per-process listener management

    private func refreshPerProcessListeners() {
        let current = Set(fetchProcessObjectList())
        let previous = Set(perProcessBlocks.keys)

        for objectID in previous.subtracting(current) {
            if let block = perProcessBlocks.removeValue(forKey: objectID) {
                removeIsRunningInputListener(objectID: objectID, block: block)
            }
        }

        for objectID in current.subtracting(previous) {
            installIsRunningInputListener(objectID: objectID)
        }

        // Inform the allowlist of everything currently in CoreAudio (for the
        // "Also detected on this Mac" section in Settings).
        let allBundleIDs = current.compactMap { pid(for: $0) }.compactMap { resolvedBundleID(for: $0) }
        allowlist?.updateDiscovered(allBundleIDs)
    }

    private func installIsRunningInputListener(objectID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.reevaluateTriggerState() }
        }
        perProcessBlocks[objectID] = block
        AudioObjectAddPropertyListenerBlock(objectID, &address, nil, block)
    }

    private func removeIsRunningInputListener(objectID: AudioObjectID, block: @escaping AudioObjectPropertyListenerBlock) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(objectID, &address, nil, block)
    }

    // MARK: - Trigger evaluation

    private func reevaluateTriggerState() {
        let enabledIDs = allowlist?.enabledBundleIDs ?? Set(MicAllowlist.defaultAllowlist.keys)

        var newActive: Set<pid_t> = []
        for objectID in perProcessBlocks.keys {
            guard isRunningInput(objectID: objectID),
                  let p = pid(for: objectID),
                  let bundleID = resolvedBundleID(for: p),
                  enabledIDs.contains(bundleID)
            else { continue }
            newActive.insert(p)
        }

        let wasActive = !activeMeetingPIDs.isEmpty
        let isNowActive = !newActive.isEmpty
        activeMeetingPIDs = newActive

        if isNowActive && !wasActive {
            onMicGrabbed?()
        } else if !isNowActive && wasActive {
            onMicReleased?()
        }
    }

    // MARK: - CoreAudio helpers

    private func fetchProcessObjectList() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private func pid(for objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func isRunningInput(objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    // MARK: - Bundle ID resolution

    private func resolvedBundleID(for pid: pid_t) -> String? {
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier {
            return rootAppBundleID(for: bundleID)
        }
        // Fallback: check parent PID (handles browser helper processes).
        if let ppid = parentPID(of: pid),
           let app = NSRunningApplication(processIdentifier: ppid),
           let bundleID = app.bundleIdentifier {
            return rootAppBundleID(for: bundleID)
        }
        return nil
    }

    /// Strips helper suffixes so `com.google.Chrome.helper.Renderer` → `com.google.Chrome`.
    private func rootAppBundleID(for bundleID: String) -> String {
        let suffixes = [".helper.Renderer", ".helper.GPU", ".helper.Plugin", ".helper", ".xpc"]
        var result = bundleID
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes where result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                changed = true
            }
        }
        return result
    }

    private func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }
}
