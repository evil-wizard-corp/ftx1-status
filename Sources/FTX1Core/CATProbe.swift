import Foundation

public enum CATProbe {
    public static let candidateBauds = [38400, 4800, 9600, 19200, 115200]

    /// Read-only CAT queries (ID, FA, MD0). Tries `preferred` first, then the rest.
    public static func run(path: String, preferred: Int?) -> CATResult {
        var order = candidateBauds
        if let p = preferred { order.removeAll { $0 == p }; order.insert(p, at: 0) }
        var tried: [Int] = []
        for baud in order {
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

        guard let id = send(fd, "ID;"), id.hasPrefix("ID") else { return .success(nil) }
        let fa = send(fd, "FA;")
        let md = send(fd, "MD0;")
        return .success(CATReading(
            baud: baud,
            radioID: parse(id, prefix: "ID"),
            frequencyHz: fa.flatMap { parse($0, prefix: "FA") }.flatMap { Int($0) },
            mode: md.flatMap { parse($0, prefix: "MD0") }.map(modeName)
        ))
    }

    private static func send(_ fd: Int32, _ cmd: String, timeout: TimeInterval = 0.4) -> String? {
        _ = cmd.withCString { write(fd, $0, strlen($0)) }
        var buf = [UInt8](), chunk = [UInt8](repeating: 0, count: 64)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, 50) > 0 else { continue }
            let n = read(fd, &chunk, chunk.count)
            if n > 0 { buf += chunk[0..<n] }
            if buf.last == UInt8(ascii: ";") { break }
        }
        guard !buf.isEmpty else { return nil }
        return String(decoding: buf, as: UTF8.self)
    }

    static func parse(_ reply: String, prefix: String) -> String? {
        guard reply.hasPrefix(prefix), reply.hasSuffix(";") else { return nil }
        return String(reply.dropFirst(prefix.count).dropLast())
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
