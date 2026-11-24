import Foundation
import CoreAudio

public enum PortHolders {
    /// path -> process names, via lsof. Gives up after `timeout` so a stuck lsof can't stall polling.
    public static func find(paths: [String], timeout: TimeInterval = 5) -> [String: [String]] {
        guard !paths.isEmpty else { return [:] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -w: no warnings for missing paths; -S 2: lsof's own timeout for blocking kernel calls.
        p.arguments = ["-w", "-S", "2", "-F", "cn", "--"] + paths
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [:] }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var command = "?"
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "c": command = value
            case "n": if !(result[value]?.contains(command) ?? false) { result[value, default: []].append(command) }
            default: break
            }
        }
        return result
    }
}

public enum AudioDevices {
    public static func names() -> [String] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &sz, &name) == noErr, let n = name else { return nil }
            return n.takeRetainedValue() as String
        }
    }
}
