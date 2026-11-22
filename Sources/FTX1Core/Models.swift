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
    public var path: String
    public var driver: String
    public var interfaceNumber: Int?
    public var interfaceName: String?
    public var usbProduct: String?
    public var usbSerial: String?
    public var vendorID: Int?
    public var productID: Int?

    public init(path: String, driver: String, interfaceNumber: Int? = nil, interfaceName: String? = nil,
                usbProduct: String? = nil, usbSerial: String? = nil, vendorID: Int? = nil, productID: Int? = nil) {
        self.path = path; self.driver = driver; self.interfaceNumber = interfaceNumber
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
    public func port(at path: String) -> SerialPort? { ports.first { $0.path == path } }

    /// Every process holding any device name that maps to the CAT interface.
    public var catHolders: [String] {
        Array(Set(catPorts.flatMap { holders[$0.path] ?? [] })).sorted()
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
    public var level: Level
    public var headline: String
    public var checks: [Check]
    public var suggestedFix: ConfigFix?
}
