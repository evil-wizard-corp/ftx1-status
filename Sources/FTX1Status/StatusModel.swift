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

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        let lastGood = UserDefaults.standard.object(forKey: baudKey) as? Int
        let wsjtx = Self.isWSJTXRunning()
        queue.async { [weak self] in
            let snap = Self.collect(lastGoodBaud: lastGood, wsjtxRunning: wsjtx)
            let report = evaluate(snap)
            Task { @MainActor in
                guard let self else { return }
                if case .ok(let r) = snap.cat { UserDefaults.standard.set(r.baud, forKey: self.baudKey) }
                self.snapshot = snap
                self.report = report
                self.inFlight = false
            }
        }
    }

    nonisolated static func collect(lastGoodBaud: Int?, wsjtxRunning: Bool) -> Snapshot {
        let ports = SerialPorts.enumerate()
        let config = WSJTXConfigFile.load()
        var paths = Set(ports.filter(\.isRadioBridge).map(\.path))
        if let p = config?.port { paths.insert(p) }
        let holders = PortHolders.find(paths: Array(paths).sorted())

        var snap = Snapshot(ports: ports, holders: holders, wsjtxRunning: wsjtxRunning, config: config,
                            cat: .skipped("Radio not found."), lastGoodBaud: lastGoodBaud,
                            audioDevices: AudioDevices.names())

        let held = snap.catHolders
        if !held.isEmpty {
            snap.cat = .skipped("CAT port in use by \(held.joined(separator: ", ")); not probing.")
        } else if let target = snap.stableCATPort ?? snap.catPorts.first {
            snap.cat = CATProbe.run(path: target.path, preferred: lastGoodBaud)
        }
        return snap
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
