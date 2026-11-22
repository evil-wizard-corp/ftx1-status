import AppKit
import FTX1Core

@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var report: Report?
    @Published var message: String?

    private let queue = DispatchQueue(label: "ftx1status.poll")
    private var timer: Timer?
    private var inFlight = false
    private let baudKey = "lastGoodBaud"

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var wsjtxRunning: Bool { snapshot?.wsjtxRunning ?? false }

    /// Last CAT probe, reused between polls so we don't touch the port every 5 s.
    private var lastProbe: (result: CATResult, at: Date, ports: [String])?
    nonisolated private static let probeInterval: TimeInterval = 60

    /// Polls USB/ports/config every call; probes CAT only when allowed (see `collect`).
    /// `forceProbe` comes from the "Probe now" button.
    func refresh(forceProbe: Bool = false) {
        guard !inFlight else { return }
        inFlight = true
        let lastGood = UserDefaults.standard.object(forKey: baudKey) as? Int
        let wsjtx = Self.isWSJTXRunning()
        let previous = lastProbe
        queue.async { [weak self] in
            let snap = Self.collect(lastGoodBaud: lastGood, wsjtxRunning: wsjtx,
                                    forceProbe: forceProbe, previous: previous)
            let report = evaluate(snap.snapshot)
            Task { @MainActor in
                guard let self else { return }
                if case .ok(let r) = snap.snapshot.cat { UserDefaults.standard.set(r.baud, forKey: self.baudKey) }
                if let fresh = snap.probed { self.lastProbe = (fresh, Date(), snap.snapshot.radioPorts.map(\.path)) }
                self.snapshot = snap.snapshot
                self.report = report
                self.inFlight = false
            }
        }
    }

    /// Probing a tty changes its baud for everyone (termios is per-device), and two readers split the
    /// reply bytes, so a probe can break WSJT-X's own CAT session. Rules:
    ///  - never probe a port someone holds open;
    ///  - never auto-probe while WSJT-X is running (checked again right before opening);
    ///  - after a successful probe, reuse it for 60 s unless the radio's ports change.
    nonisolated static func collect(lastGoodBaud: Int?, wsjtxRunning: Bool, forceProbe: Bool = false,
                                    previous: (result: CATResult, at: Date, ports: [String])? = nil)
        -> (snapshot: Snapshot, probed: CATResult?) {
        let ports = SerialPorts.enumerate()
        let config = WSJTXConfigFile.load()
        var paths = Set(ports.filter(\.isRadioBridge).map(\.path))
        if let p = config?.port { paths.insert(p) }
        let holders = PortHolders.find(paths: Array(paths).sorted())

        var snap = Snapshot(ports: ports, holders: holders, wsjtxRunning: wsjtxRunning, config: config,
                            cat: .skipped("Radio not found."), lastGoodBaud: lastGoodBaud,
                            audioDevices: AudioDevices.names())
        guard let target = snap.stableCATPort ?? snap.catPorts.first else { return (snap, nil) }

        let held = snap.catHolders
        let known = lastGoodBaud.map { " Last known rate: \($0)." } ?? ""
        if !held.isEmpty {
            snap.cat = .skipped("CAT port in use by \(held.joined(separator: ", ")); not probing.")
            return (snap, nil)
        }
        if !forceProbe && (wsjtxRunning || isWSJTXRunning()) {
            snap.cat = .skipped("WSJT-X is running, so not probing (avoids colliding with it).\(known)")
            return (snap, nil)
        }
        if !forceProbe, let prev = previous, case .ok = prev.result,
           Date().timeIntervalSince(prev.at) < probeInterval, prev.ports == snap.radioPorts.map(\.path) {
            snap.cat = prev.result
            return (snap, nil)
        }
        let result = CATProbe.run(path: target.path, preferred: lastGoodBaud)
        snap.cat = result
        return (snap, result)
    }

    nonisolated static func isWSJTXRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.executableURL?.lastPathComponent.lowercased() == "wsjtx"
        }
    }

    func applyFix() {
        guard let fix = report?.suggestedFix else { return }
        guard !Self.isWSJTXRunning() else {
            message = "Quit WSJT-X first — it overwrites its settings file on exit."
            return
        }
        do {
            let backup = try WSJTXConfigFile.apply(fix)
            message = "Updated WSJT-X.ini (backup: \(backup.lastPathComponent)). Start WSJT-X."
        } catch {
            message = "Couldn't update WSJT-X.ini: \(error.localizedDescription)"
        }
        refresh()
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText(), forType: .string)
        message = "Diagnostics copied."
    }

    func diagnosticsText() -> String {
        guard let s = snapshot, let r = report else { return "No data yet." }
        return FTX1Core.diagnosticsText(s, r)
    }
}
