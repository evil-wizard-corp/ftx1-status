import Foundation

public enum Level: Int, Comparable, Sendable {
    case ok, info, warn, error
    public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
}

/// CP2105 dual UART inside the FTX-1: interface 0 = Enhanced (CAT), interface 1 = Standard (PTT/RTS).
public let radioBridgeVendorID = 0x10C4
public let radioBridgeProductID = 0xEA70

public enum PortRole: String, Sendable { case cat = "CAT (Enhanced)", ptt = "PTT (Standard)" }

public struct SerialPort: Equatable, Sendable {
    /// The callout device (/dev/cu.*), which is what WSJT-X should use.
    public var path: String
    /// The dial-in device (/dev/tty.*) for the same UART. Some apps list and open this name instead.
    public var dialinPath: String?
    public var driver: String
    public var interfaceNumber: Int?
    public var interfaceName: String?
    public var usbProduct: String?
    public var usbSerial: String?
    public var vendorID: Int?
    public var productID: Int?

    public init(path: String, dialinPath: String? = nil, driver: String, interfaceNumber: Int? = nil,
                interfaceName: String? = nil, usbProduct: String? = nil, usbSerial: String? = nil,
                vendorID: Int? = nil, productID: Int? = nil) {
        self.path = path; self.dialinPath = dialinPath; self.driver = driver; self.interfaceNumber = interfaceNumber
        self.interfaceName = interfaceName; self.usbProduct = usbProduct; self.usbSerial = usbSerial
        self.vendorID = vendorID; self.productID = productID
    }

    public var isRadioBridge: Bool { vendorID == radioBridgeVendorID && productID == radioBridgeProductID }

    public var role: PortRole? {
        guard isRadioBridge else { return nil }
        switch interfaceNumber { case 0: return .cat; case 1: return .ptt; default: return nil }
    }

    /// Apple's driver names ports after the chip's USB serial number, so the name survives reboots.
    /// The Silicon Labs driver uses SLAB_USBtoUART<n>, where n depends on enumeration order.
    public var hasStableName: Bool { path.contains("usbserial-") }

    public var displayName: String { (path as NSString).lastPathComponent }

    /// Both device names for this UART.
    public var allPaths: [String] { [path] + (dialinPath.map { [$0] } ?? []) }
    public func matches(_ devicePath: String) -> Bool { allPaths.contains(devicePath) }
}

public struct CATReading: Equatable, Sendable {
    public var baud: Int
    public var radioID: String?
    public var frequencyHz: Int?
    public var mode: String?
    public init(baud: Int, radioID: String?, frequencyHz: Int?, mode: String?) {
        self.baud = baud; self.radioID = radioID; self.frequencyHz = frequencyHz; self.mode = mode
    }
}

public enum CATResult: Equatable, Sendable {
    case ok(CATReading)
    case noReply(triedBauds: [Int])
    case skipped(String)
    case openFailed(String)

    /// One line for the diagnostics text.
    public var summary: String {
        switch self {
        case .ok(let r):
            let freq = r.frequencyHz.map { String(format: "%.6f MHz", Double($0) / 1e6) } ?? "frequency ?"
            return "answered at \(r.baud) baud (ID \(r.radioID ?? "?"), \(freq), \(r.mode ?? "mode ?"))"
        case .noReply(let tried): return "no reply at \(tried.map(String.init).joined(separator: "/"))"
        case .skipped(let why): return "not probed: \(why)"
        case .openFailed(let why): return "couldn't open port: \(why)"
        }
    }
}

public struct WSJTXConfig: Equatable, Sendable {
    public var rig: String?
    public var port: String?
    public var baud: Int?
    public var pttMethod: String?
    public var soundIn: String?
    public var soundOut: String?
    public init(rig: String? = nil, port: String? = nil, baud: Int? = nil, pttMethod: String? = nil,
                soundIn: String? = nil, soundOut: String? = nil) {
        self.rig = rig; self.port = port; self.baud = baud; self.pttMethod = pttMethod
        self.soundIn = soundIn; self.soundOut = soundOut
    }

    /// WSJT-X can reach the radio through flrig or a Hamlib rigctld server instead of a serial port.
    /// Then that server holds the CAT port, and CATSerialPort/CATSerialRate don't matter.
    public var usesRigServer: Bool {
        guard let rig = rig?.lowercased() else { return false }
        return rig.contains("flrig") || rig.contains("net rigctl")
    }
}

public struct Snapshot: Sendable {
    public var ports: [SerialPort]
    /// device path -> process names holding it open
    public var holders: [String: [String]]
    public var wsjtxRunning: Bool
    public var config: WSJTXConfig?
    public var cat: CATResult
    public var lastGoodBaud: Int?
    public var audioDevices: [String]
    public var timestamp: Date

    public init(ports: [SerialPort], holders: [String: [String]], wsjtxRunning: Bool, config: WSJTXConfig?,
                cat: CATResult, lastGoodBaud: Int?, audioDevices: [String], timestamp: Date = Date()) {
        self.ports = ports; self.holders = holders; self.wsjtxRunning = wsjtxRunning; self.config = config
        self.cat = cat; self.lastGoodBaud = lastGoodBaud; self.audioDevices = audioDevices; self.timestamp = timestamp
    }

    public var radioPorts: [SerialPort] { ports.filter(\.isRadioBridge) }
    public var catPorts: [SerialPort] { radioPorts.filter { $0.role == .cat } }
    public var stableCATPort: SerialPort? { catPorts.first(where: \.hasStableName) }
    /// The port with this cu.* or tty.* name.
    public func port(at path: String) -> SerialPort? { ports.first { $0.matches(path) } }

    /// Processes holding either of a port's device names.
    public func holders(of port: SerialPort) -> [String] {
        Array(Set(port.allPaths.flatMap { holders[$0] ?? [] })).sorted()
    }

    /// Every process holding any device name that maps to the CAT interface.
    public var catHolders: [String] {
        Array(Set(catPorts.flatMap { holders(of: $0) })).sorted()
    }
}

public struct Check: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var title: String
    public var level: Level
    public var detail: String
}

public struct ConfigFix: Equatable, Sendable {
    public var port: String
    public var baud: Int
}

public struct Report: Sendable {
    /// False when the radio isn't on USB, which is normal when it's switched off.
    public var radioConnected: Bool = true
    public var level: Level
    public var headline: String
    public var checks: [Check]
    public var suggestedFix: ConfigFix?
}
