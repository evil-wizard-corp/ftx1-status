import Foundation

public func diagnosticsText(_ s: Snapshot, _ r: Report) -> String {
    var out = ["FTX-1 Status — \(s.timestamp.formatted())", "Overall: \(r.level) — \(r.headline)", "", "Checks:"]
    out += r.checks.map { "  [\($0.level)] \($0.title): \($0.detail)" }
    out += ["", "Serial ports:"]
    for p in s.ports {
        let role = p.role?.rawValue ?? "-"
        let held = s.holders[p.path].map { " held by \($0.joined(separator: ","))" } ?? ""
        out.append("  \(p.path)  role=\(role) driver=\(p.driver) usb=\(p.usbProduct ?? "-")\(held)")
    }
    if let c = s.config {
        out += ["", "WSJT-X.ini: rig=\(c.rig ?? "-") port=\(c.port ?? "-") baud=\(c.baud.map(String.init) ?? "-") ptt=\(c.pttMethod ?? "-") in=\(c.soundIn ?? "-") out=\(c.soundOut ?? "-")"]
    }
    out += ["WSJT-X running: \(s.wsjtxRunning)", "CAT: \(s.cat)", "Audio devices: \(s.audioDevices.joined(separator: ", "))"]
    return out.joined(separator: "\n")
}
