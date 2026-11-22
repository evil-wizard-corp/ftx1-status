import Foundation

public enum WSJTXConfigFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/WSJT-X.ini")
    }

    public static func load(from url: URL = defaultURL) -> WSJTXConfig? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Reads the keys we care about. First occurrence wins (WSJT-X keeps the active config under [Configuration]).
    public static func parse(_ text: String) -> WSJTXConfig {
        var kv: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            if kv[key] == nil { kv[key] = String(line[line.index(after: eq)...]) }
        }
        return WSJTXConfig(
            rig: kv["Rig"],
            port: kv["CATSerialPort"].flatMap { $0.isEmpty ? nil : $0 },
            baud: kv["CATSerialRate"].flatMap { Int($0) },
            pttMethod: kv["PTTMethod"].flatMap(qtEnumValue),
            soundIn: kv["SoundInName"],
            soundOut: kv["SoundOutName"]
        )
    }

    /// Qt serializes enums as @Variant(...\x10PTT_method_CAT\0); pull out the readable token.
    static func qtEnumValue(_ raw: String) -> String? {
        let tokens = decodeQtEscapes(raw).split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
        return tokens.last(where: { $0.contains("_") }).map(String.init)
    }

    /// QSettings escapes bytes as \xHH (greedy hex, so a following hex-looking char is escaped too) and \0, \r, etc.
    static func decodeQtEscapes(_ s: String) -> String {
        var out = "", chars = Array(s), i = 0
        while i < chars.count {
            guard chars[i] == "\\", i + 1 < chars.count else { out.append(chars[i]); i += 1; continue }
            let next = chars[i + 1]
            if next == "x" {
                var j = i + 2, hex = ""
                while j < chars.count, chars[j].isHexDigit { hex.append(chars[j]); j += 1 }
                if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
                i = j
            } else {
                out.append(next == "\\" ? "\\" : "\u{0}")
                i += 2
            }
        }
        return out
    }

    /// Rewrites CATSerialPort / CATSerialRate in place. Only call when WSJT-X is not running —
    /// it rewrites the file on quit. Returns the backup URL.
    @discardableResult
    public static func apply(_ fix: ConfigFix, to url: URL = defaultURL) throws -> URL {
        let original = try String(contentsOf: url, encoding: .utf8)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appendingPathComponent("WSJT-X.ini.bak-\(stamp)")
        try original.write(to: backup, atomically: true, encoding: .utf8)
        try rewrite(original, fix).write(to: url, atomically: true, encoding: .utf8)
        return backup
    }

    public static func rewrite(_ text: String, _ fix: ConfigFix) -> String {
        var lines = text.components(separatedBy: "\n")
        var sawPort = false, sawRate = false
        for i in lines.indices {
            if lines[i].hasPrefix("CATSerialPort=") && !sawPort { lines[i] = "CATSerialPort=\(fix.port)"; sawPort = true }
            else if lines[i].hasPrefix("CATSerialRate=") && !sawRate { lines[i] = "CATSerialRate=\(fix.baud)"; sawRate = true }
        }
        return lines.joined(separator: "\n")
    }
}
