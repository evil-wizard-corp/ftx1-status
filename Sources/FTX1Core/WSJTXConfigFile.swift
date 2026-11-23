import Foundation

public enum WSJTXConfigFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/WSJT-X.ini")
    }

    /// WSJT-X keeps the active configuration's settings in this QSettings group. Other saved
    /// configurations live under [MultiSettings] with prefixed keys, so they never collide.
    static let section = "Configuration"

    public static func load(from url: URL = defaultURL) -> WSJTXConfig? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Reads the keys we care about from [Configuration] (or the whole file if it has no such section).
    /// First occurrence wins.
    public static func parse(_ text: String) -> WSJTXConfig {
        let lines = text.components(separatedBy: "\n")
        var kv: [String: String] = [:]
        for i in sectionRange(lines) {
            guard let (key, value) = keyValue(lines[i]) else { continue }
            if kv[key] == nil { kv[key] = value }
        }
        let string = { (key: String) in kv[key].map(decodeQtString) }
        return WSJTXConfig(
            rig: string("Rig"),
            port: string("CATSerialPort").flatMap { $0.isEmpty ? nil : $0 },
            baud: string("CATSerialRate").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            pttMethod: kv["PTTMethod"].flatMap(qtEnumValue),
            soundIn: string("SoundInName"),
            soundOut: string("SoundOutName")
        )
    }

    /// Line indices of the [Configuration] section's body, or of every line if the section is missing.
    static func sectionRange(_ lines: [String]) -> Range<Int> {
        guard let header = lines.firstIndex(where: { sectionName($0) == section }) else { return lines.indices }
        let end = lines[(header + 1)...].firstIndex(where: { sectionName($0) != nil }) ?? lines.endIndex
        return (header + 1)..<end
    }

    static func sectionName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), t.hasSuffix("]"), t.count >= 2 else { return nil }
        return String(t.dropFirst().dropLast())
    }

    static func keyValue(_ line: String) -> (String, String)? {
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
        guard sectionName(line) == nil, let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        return (key, String(line[line.index(after: eq)...]))
    }

    /// Qt serializes enums as @Variant(...\x10PTT_method_CAT\0); pull out the readable token.
    static func qtEnumValue(_ raw: String) -> String? {
        let tokens = decodeQtEscapes(raw).split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
        return tokens.last(where: { $0.contains("_") }).map(String.init)
    }

    /// A QSettings string value: strips the quotes QSettings adds around values with commas or
    /// leading/trailing spaces, decodes escapes (non-ASCII device names are written as \xHHHH),
    /// and turns the "@@" escape back into "@".
    static func decodeQtString(_ raw: String) -> String {
        var s = decodeQtEscapes(raw, stripQuotes: true)
        if s.hasPrefix("@@") { s.removeFirst() }
        return s
    }

    /// Undoes QSettings' INI escaping: \a \b \f \n \r \t \v \" \' \? \\, \0-\7 octal, and \xHHHH.
    /// Hex escapes are greedy, which is why QSettings escapes a hex-looking character that follows one.
    static func decodeQtEscapes(_ s: String, stripQuotes: Bool = false) -> String {
        let chars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView(), i = 0
        func scalar(_ digits: [Unicode.Scalar], radix: Int) -> Unicode.Scalar? {
            UInt32(String(String.UnicodeScalarView(digits)), radix: radix).flatMap(Unicode.Scalar.init)
        }
        while i < chars.count {
            let c = chars[i]
            if stripQuotes && c == "\"" { i += 1; continue }
            guard c == "\\", i + 1 < chars.count else { out.append(c); i += 1; continue }
            let next = chars[i + 1]
            i += 2
            switch next {
            case "x":
                var j = i
                while j < chars.count, chars[j].properties.isASCIIHexDigit { j += 1 }
                if let u = scalar(Array(chars[i..<j]), radix: 16) { out.append(u) }
                i = j
            case "0"..."7":
                var j = i
                while j < chars.count, j < i + 2, ("0"..."7").contains(chars[j]) { j += 1 }
                if let u = scalar([next] + chars[i..<j], radix: 8) { out.append(u) }
                i = j
            case "a": out.append("\u{07}")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "v": out.append("\u{0B}")
            default: out.append(next)  // \" \' \? \\ and anything unknown
            }
        }
        return String(out)
    }

    public enum ApplyError: LocalizedError {
        case notApplied
        public var errorDescription: String? { "the file didn't contain the new settings after writing" }
    }

    /// Rewrites CATSerialPort / CATSerialRate. Only call when WSJT-X is not running —
    /// it rewrites the file on quit. Returns the backup URL.
    @discardableResult
    public static func apply(_ fix: ConfigFix, to url: URL = defaultURL) throws -> URL {
        // Write through symlinks (e.g. a dotfiles-managed ini) instead of replacing them.
        let url = url.resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        guard let original = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).bak-\(stamp)")
        try data.write(to: backup)
        let updated = rewrite(original, fix)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        let check = parse(updated)
        guard check.port == fix.port, check.baud == fix.baud else { throw ApplyError.notApplied }
        return backup
    }

    /// Sets CATSerialPort / CATSerialRate in [Configuration], adding the keys (or the section) if missing.
    public static func rewrite(_ text: String, _ fix: ConfigFix) -> String {
        var lines = text.components(separatedBy: "\n")
        let wanted = [("CATSerialPort", fix.port), ("CATSerialRate", String(fix.baud))]
        let hasSection = lines.contains { sectionName($0) == section }
        let range = sectionRange(lines)
        var missing: [String] = []
        for (key, value) in wanted {
            let cr = lines.contains { $0.hasSuffix("\r") } ? "\r" : ""
            if let i = range.first(where: { keyValue(lines[$0])?.0 == key }) {
                lines[i] = "\(key)=\(value)\(lines[i].hasSuffix("\r") ? "\r" : "")"
            } else {
                missing.append("\(key)=\(value)\(cr)")
            }
        }
        guard !missing.isEmpty else { return lines.joined(separator: "\n") }

        if hasSection {
            // Insert after the section's last non-blank line.
            var at = range.upperBound
            while at > range.lowerBound, lines[at - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { at -= 1 }
            lines.insert(contentsOf: missing, at: at)
        } else {
            if let last = lines.last, last.isEmpty { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            lines += ["[\(section)]"] + missing + [""]
        }
        return lines.joined(separator: "\n")
    }
}
