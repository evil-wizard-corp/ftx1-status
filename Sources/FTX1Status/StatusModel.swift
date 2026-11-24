import AppKit
import FTX1Core
import ServiceManagement

@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var report: Report?
    @Published private(set) var message: String?
    @Published private(set) var launchAtLogin = false

    private let queue = DispatchQueue(label: "ftx1status.poll")
    private var timer: Timer?
    private var inFlight = false
    private var pendingForceProbe = false
    private var messageClear: DispatchWorkItem?
    private let baudKey = "lastGoodBaud"

    nonisolated static var appVersion: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    init() {
        refresh()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // .common so polling keeps going while the menu's window is tracking events.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var wsjtxRunning: Bool { snapshot?.wsjtxRunning ?? false }

    /// Last CAT probe, reused between polls so we don't touch the port every 5 s.
    private var lastProbe: Probe?
    typealias Probe = (result: CATResult, at: Date, ports: [String])

    /// Polls USB/ports/config every call; probes CAT only when allowed (see `collect`).
    /// `forceProbe` comes from the "Probe now" button.
    func refresh(forceProbe: Bool = false) {
        guard !inFlight else {
            // Don't drop a button press just because a timer poll is running.
            if forceProbe { pendingForceProbe = true }
            return
        }
        inFlight = true
        let loginEnabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != loginEnabled { launchAtLogin = loginEnabled }
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
                if self.pendingForceProbe {
                    self.pendingForceProbe = false
                    self.refresh(forceProbe: true)
                }
            }
        }
    }

    /// How long a probe result is reused. A failure is retried sooner so fixing the radio's
    /// CAT RATE shows up quickly, but not every poll (each failed probe holds the port ~2 s).
    nonisolated static func reuseInterval(for result: CATResult) -> TimeInterval {
        if case .ok = result { return 60 }
        return 15
    }

    /// Probing a tty changes its baud for everyone (termios is per-device), and two readers split the
    /// reply bytes, so a probe can break WSJT-X's own CAT session. Rules:
    ///  - never probe a port someone holds open;
    ///  - never auto-probe while WSJT-X is running (checked again right before opening);
    ///  - reuse the last probe for a while (see `reuseInterval`) unless the radio's ports change.
    nonisolated static func collect(lastGoodBaud: Int?, wsjtxRunning: Bool, forceProbe: Bool = false,
                                    previous: Probe? = nil) -> (snapshot: Snapshot, probed: CATResult?) {
        let ports = SerialPorts.enumerate()
        let config = WSJTXConfigFile.load()
        var paths = Set(ports.filter(\.isRadioBridge).map(\.path))
        if let p = config?.port { paths.insert(p) }
        let holders = PortHolders.find(paths: Array(paths).sorted())

        var snap = Snapshot(ports: ports, holders: holders, wsjtxRunning: wsjtxRunning, config: config,
                            cat: .skipped("Radio not found."), lastGoodBaud: lastGoodBaud,
                            audioDevices: AudioDevices.names())
        guard let target = snap.stableCATPort ?? snap.catPorts.first else {
            if !snap.radioPorts.isEmpty { snap.cat = .skipped("No CAT port to probe.") }
            return (snap, nil)
        }

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
        if !forceProbe, let prev = previous, Date().timeIntervalSince(prev.at) < reuseInterval(for: prev.result),
           prev.ports == snap.radioPorts.map(\.path) {
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

    /// Shows a status line under the checks; it clears itself after a while.
    func show(_ text: String, for seconds: TimeInterval = 10) {
        message = text
        messageClear?.cancel()
        let clear = DispatchWorkItem { [weak self] in
            Task { @MainActor in if self?.message == text { self?.message = nil } }
        }
        messageClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: clear)
    }

    func applyFix() {
        guard let fix = report?.suggestedFix else { return }
        guard !Self.isWSJTXRunning() else {
            show("Quit WSJT-X first — it overwrites its settings file on exit.")
            return
        }
        do {
            let backup = try WSJTXConfigFile.apply(fix)
            show("Updated WSJT-X.ini (backup: \(backup.lastPathComponent)). Start WSJT-X.", for: 30)
        } catch {
            show("Couldn't update WSJT-X.ini: \(error.localizedDescription)", for: 30)
        }
        refresh()
    }

    func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            show("Launch at login: \(error.localizedDescription)", for: 30)
        }
        if on && service.status == .requiresApproval {
            show("Allow FTX1 Status in System Settings → General → Login Items.", for: 30)
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = service.status == .enabled
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText(), forType: .string)
        show("Diagnostics copied.", for: 4)
    }

    func diagnosticsText() -> String {
        guard let s = snapshot, let r = report else { return "No data yet." }
        return FTX1Core.diagnosticsText(s, r, appVersion: Self.appVersion)
    }
}
