import Foundation

public enum CATProbe {
    public static let candidateBauds = [38400, 4800, 9600, 19200, 115200]

    /// Read-only CAT queries (ID, FA, MD0). Tries `preferred` first, then the rest.
    /// `stopReason` runs before each baud; returning a reason stops the probe (say, WSJT-X just
    /// started and is about to open the port), and the result is `.skipped(reason)`.
    public static func run(path: String, preferred: Int?, stopReason: () -> String? = { nil }) -> CATResult {
        var order = candidateBauds
        if let p = preferred { order.removeAll { $0 == p }; order.insert(p, at: 0) }
        var tried: [Int] = []
        for baud in order {
            if let why = stopReason() { return .skipped(why) }
            tried.append(baud)
            switch query(path: path, baud: baud) {
            case .failure(let f): return .openFailed(f.message)
            case .success(let reading?): return .ok(reading)
            case .success(nil): continue
            }
        }
        return .noReply(triedBauds: tried)
    }

    static func query(path: String, baud: Int) -> Result<CATReading?, Failure> {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return .failure(Failure(String(cString: strerror(errno)))) }
        defer { close(fd) }

        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        cfsetspeed(&t, speed_t(baud))
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { return .failure(Failure("tcsetattr: \(String(cString: strerror(errno)))")) }
        tcflush(fd, TCIOFLUSH)

        // Yaesu IDs are four digits; anything else is line noise at the wrong baud.
        // The leading ";" ends any half-command left in the radio's buffer by bytes sent at a wrong baud,
        // so the ID query isn't read as "<junk>ID;". The radio may answer it with "?;", which is ignored.
        guard let id = send(fd, ";ID;", expect: "ID"), id.count == 4, id.allSatisfy(\.isASCII), id.allSatisfy(\.isNumber)
        else { return .success(nil) }
        let fa = send(fd, "FA;", expect: "FA")
        let md = send(fd, "MD0;", expect: "MD0")
        return .success(CATReading(
            baud: baud,
            radioID: id,
            frequencyHz: fa.flatMap { Int($0) },
            mode: md.map(modeName)
        ))
    }

    /// Sends `cmd` and waits for a reply starting with `expect`; returns the reply's payload.
    private static func send(_ fd: Int32, _ cmd: String, expect: String, timeout: TimeInterval = 0.4) -> String? {
        let bytes = Array(cmd.utf8)
        guard write(fd, bytes, bytes.count) == bytes.count else { return nil }
        var buf = [UInt8](), chunk = [UInt8](repeating: 0, count: 64)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, 50) > 0 else { continue }
            let n = read(fd, &chunk, chunk.count)
            if n > 0 { buf += chunk[0..<n] }
            if buf.last == UInt8(ascii: ";"), let reply = extract(String(decoding: buf, as: UTF8.self), prefix: expect) {
                return reply
            }
        }
        return nil
    }

    /// Finds the first complete `<prefix>...;` reply in `raw` and returns what follows the prefix.
    /// Tolerates other replies in the stream (the radio's Auto Information mode sends unsolicited
    /// FA/MD updates) and line noise in front of a reply.
    static func extract(_ raw: String, prefix: String) -> String? {
        var tokens = raw.split(separator: ";", omittingEmptySubsequences: false)
        tokens.removeLast()  // text after the last ';' is incomplete
        for token in tokens {
            let t = token.drop { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            if t.hasPrefix(prefix) { return String(t.dropFirst(prefix.count)) }
        }
        return nil
    }

    /// Yaesu mode codes (FTDX10/FTX-1 family).
    static func modeName(_ code: String) -> String {
        let map = ["1": "LSB", "2": "USB", "3": "CW-U", "4": "FM", "5": "AM", "6": "RTTY-L", "7": "CW-L",
                   "8": "DATA-L", "9": "RTTY-U", "A": "DATA-FM", "B": "FM-N", "C": "DATA-U", "D": "AM-N",
                   "E": "PSK", "F": "DATA-FM-N"]
        return map[code] ?? "mode \(code)"
    }

    public struct Failure: Error { public let message: String; init(_ m: String) { message = m } }
}
