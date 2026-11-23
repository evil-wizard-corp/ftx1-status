import Foundation

/// Turns a raw snapshot into a list of checks plus an overall verdict. Pure, so it is unit tested.
public func evaluate(_ s: Snapshot) -> Report {
    var checks: [Check] = []

    // 1. Is the radio on USB at all?
    guard !s.radioPorts.isEmpty else {
        checks.append(Check(title: "Radio on USB", level: .error,
                            detail: "No CP2105 (10C4:EA70) found. Radio is off, USB cable unplugged, or still booting."))
        checks.append(wsjtxRunningCheck(s, catConnected: false))
        return finish(checks, fix: nil)
    }
    let serial = s.radioPorts.first?.usbSerial ?? "?"
    checks.append(Check(title: "Radio on USB", level: .ok, detail: "CP2105 present (serial \(serial))."))

    // 2. CAT port names.
    let catNames = s.catPorts.map(\.displayName).joined(separator: ", ")
    if s.catPorts.isEmpty {
        checks.append(Check(title: "CAT port", level: .error,
                            detail: "CP2105 found but no serial device for interface 0 (Enhanced)."))
    } else {
        checks.append(Check(title: "CAT port", level: .ok, detail: catNames))
    }

    // 3. Does the radio answer?
    let knownBaud: Int?
    switch s.cat {
    case .ok(let r):
        knownBaud = r.baud
        let id = r.radioID.map { $0 == "0840" ? "FTX-1" : "ID \($0)" } ?? "radio"
        checks.append(Check(title: "CAT reply", level: .ok, detail: "\(id) answers at \(r.baud) baud."))
    case .noReply(let tried):
        knownBaud = nil
        checks.append(Check(title: "CAT reply", level: .error,
                            detail: "No answer at \(tried.map(String.init).joined(separator: "/")). Check the radio's CAT RATE and that CAT is enabled."))
    case .skipped(let why):
        knownBaud = s.lastGoodBaud
        let held = s.catHolders
        let level: Level = held.isEmpty || held.contains(where: isWSJTX) ? .info : .warn
        checks.append(Check(title: "CAT reply", level: level, detail: why))
    case .openFailed(let why):
        knownBaud = s.lastGoodBaud
        checks.append(Check(title: "CAT reply", level: .warn, detail: "Couldn't open CAT port: \(why)"))
    }

    // 4. WSJT-X configuration.
    var fix: ConfigFix?
    if let cfg = s.config {
        let live: Bool
        if case .ok = s.cat { live = true } else { live = false }
        checks.append(contentsOf: configChecks(cfg, s, knownBaud: knownBaud, live: live))
        if let port = suggestedPort(cfg, s), let baud = knownBaud, cfg.port != port || cfg.baud != baud {
            fix = ConfigFix(port: port, baud: baud)
        }
    } else {
        checks.append(Check(title: "WSJT-X config", level: .info, detail: "WSJT-X.ini not found."))
    }

    // 5. Is WSJT-X actually connected?
    checks.append(wsjtxRunningCheck(s, catConnected: s.catHolders.contains(where: isWSJTX)))

    return finish(checks, fix: fix)
}

/// The stable (usbserial-) CAT name if there is one; otherwise keep the configured port if it's
/// already CAT, else any CAT name. Only the Silicon Labs driver's SLAB names exist on some Macs.
func suggestedPort(_ cfg: WSJTXConfig, _ s: Snapshot) -> String? {
    if let stable = s.stableCATPort { return stable.path }
    if let current = s.catPorts.first(where: { $0.path == cfg.port }) { return current.path }
    return s.catPorts.first?.path
}

/// `live` says `knownBaud` came from a probe just now rather than from the last good probe.
func configChecks(_ cfg: WSJTXConfig, _ s: Snapshot, knownBaud: Int?, live: Bool = true) -> [Check] {
    var out: [Check] = []

    if let rig = cfg.rig, !rig.localizedCaseInsensitiveContains("FTX-1") {
        out.append(Check(title: "WSJT-X rig", level: .warn, detail: "Rig is set to \"\(rig)\", not Yaesu FTX-1."))
    }

    let stableHint = s.stableCATPort.map { " Use \($0.path)." } ?? ""
    if let path = cfg.port {
        let name = (path as NSString).lastPathComponent
        if let p = s.port(at: path) {
            switch p.role {
            case .cat where p.hasStableName:
                out.append(Check(title: "WSJT-X port", level: .ok, detail: "\(name) → CAT, stable name."))
            case .cat where s.stableCATPort != nil:
                out.append(Check(title: "WSJT-X port", level: .warn,
                                 detail: "\(name) is CAT right now, but SLAB names move between boots.\(stableHint)"))
            case .cat:
                // No usbserial- name to switch to, so there's nothing to fix; we'll flag it if the name moves.
                out.append(Check(title: "WSJT-X port", level: .info,
                                 detail: "\(name) → CAT. SLAB names can move between boots; this check will catch it."))
            case .ptt:
                out.append(Check(title: "WSJT-X port", level: .error,
                                 detail: "\(name) is the PTT (Standard) port on this boot, not CAT.\(stableHint)"))
            case nil:
                out.append(Check(title: "WSJT-X port", level: .error,
                                 detail: "\(name) isn't the radio.\(stableHint)"))
            }
        } else {
            out.append(Check(title: "WSJT-X port", level: .error, detail: "\(name) doesn't exist right now.\(stableHint)"))
        }
    } else {
        out.append(Check(title: "WSJT-X port", level: .warn, detail: "No CAT serial port configured."))
    }

    if let want = knownBaud, let have = cfg.baud {
        if want == have {
            out.append(Check(title: "WSJT-X baud", level: .ok, detail: "\(have)"))
        } else {
            // A remembered rate may be stale (the radio's CAT RATE was changed since), so only warn.
            out.append(live
                ? Check(title: "WSJT-X baud", level: .error, detail: "WSJT-X uses \(have), radio answers at \(want).")
                : Check(title: "WSJT-X baud", level: .warn, detail: "WSJT-X uses \(have), radio last answered at \(want)."))
        }
    } else if let have = cfg.baud {
        out.append(Check(title: "WSJT-X baud", level: .info, detail: "\(have) (radio's rate not known yet)"))
    }

    for (label, name) in [("Audio in", cfg.soundIn), ("Audio out", cfg.soundOut)] {
        guard let name, !name.isEmpty else { continue }
        if s.audioDevices.contains(name) {
            out.append(Check(title: label, level: .ok, detail: name))
        } else {
            out.append(Check(title: label, level: .error, detail: "\"\(name)\" isn't connected."))
        }
    }
    return out
}

func wsjtxRunningCheck(_ s: Snapshot, catConnected: Bool) -> Check {
    let others = s.catHolders.filter { !isWSJTX($0) }
    if !others.isEmpty {
        return Check(title: "WSJT-X link", level: .warn,
                     detail: "\(others.joined(separator: ", ")) has the CAT port open, so WSJT-X can't use it.")
    }
    if !s.wsjtxRunning {
        return Check(title: "WSJT-X link", level: .info, detail: "WSJT-X isn't running.")
    }
    if catConnected {
        return Check(title: "WSJT-X link", level: .ok, detail: "WSJT-X has the CAT port open.")
    }
    let wrong = s.holders.filter { $0.value.contains(where: isWSJTX) }.map { ($0.key as NSString).lastPathComponent }
    let detail = wrong.isEmpty ? "WSJT-X is running but hasn't opened the CAT port."
                               : "WSJT-X is running but holds \(wrong.sorted().joined(separator: ", ")), not the CAT port."
    return Check(title: "WSJT-X link", level: .error, detail: detail)
}

func isWSJTX(_ process: String) -> Bool { process.lowercased().hasPrefix("wsjtx") }

func finish(_ checks: [Check], fix: ConfigFix?) -> Report {
    let level = checks.map(\.level).max() ?? .ok
    let headline: String
    if let worst = checks.first(where: { $0.level == level && level >= .warn }) {
        headline = worst.detail
    } else {
        headline = "All good"
    }
    return Report(level: level, headline: headline, checks: checks, suggestedFix: fix)
}
