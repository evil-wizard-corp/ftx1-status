import SwiftUI
import FTX1Core
import ServiceManagement

struct MenuView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let s = model.snapshot, let r = model.report {
                radioLine(s)
                Divider()
                checks(r)
                Divider()
                ports(s)
                if let c = s.config { Divider(); config(c) }
                if let fix = r.suggestedFix { Divider(); fixBox(fix) }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let m = model.message {
                Text(m).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            let level = model.report?.level ?? .info
            Image(systemName: level.symbol).foregroundStyle(level.swiftUIColor).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("FTX-1 Status").font(.headline)
                Text(model.report?.headline ?? "Checking…")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func radioLine(_ s: Snapshot) -> some View {
        if case .ok(let r) = s.cat {
            HStack {
                Text(r.frequencyHz.map { String(format: "%.4f MHz", Double($0) / 1e6) } ?? "—")
                    .font(.system(.title3, design: .monospaced))
                Text(r.mode ?? "").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("\(r.baud) baud").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func checks(_ r: Report) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(r.checks) { c in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: c.level.symbol).foregroundStyle(c.level.swiftUIColor).font(.caption)
                    Text(c.title).font(.caption.bold()).frame(width: 90, alignment: .leading)
                    Text(c.detail).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func ports(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Radio serial ports").font(.caption.bold()).foregroundStyle(.secondary)
            if s.radioPorts.isEmpty {
                Text("none").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(s.radioPorts, id: \.path) { p in
                HStack(spacing: 6) {
                    Text(p.displayName).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Text(p.role == .cat ? "CAT" : "PTT").font(.caption2.bold())
                        .foregroundStyle(p.role == .cat ? .green : .secondary)
                    Text(p.driver).font(.caption2).foregroundStyle(.secondary)
                    if let h = s.holders[p.path] {
                        Text("← \(h.joined(separator: ","))").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func config(_ c: WSJTXConfig) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("WSJT-X settings").font(.caption.bold()).foregroundStyle(.secondary)
            Text("\(c.port.map { ($0 as NSString).lastPathComponent } ?? "—") @ \(c.baud.map(String.init) ?? "—") · PTT \(c.pttMethod?.replacingOccurrences(of: "PTT_method_", with: "") ?? "—")")
                .font(.system(.caption, design: .monospaced))
            Text("Audio: \(c.soundIn ?? "—") / \(c.soundOut ?? "—")").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fixBox(_ fix: ConfigFix) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested WSJT-X settings").font(.caption.bold())
            Text("\(fix.port) @ \(fix.baud)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Button(model.wsjtxRunning ? "Quit WSJT-X to apply" : "Apply to WSJT-X.ini") { model.applyFix() }
                .disabled(model.wsjtxRunning)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { model.message = "Launch at login: \(error.localizedDescription)" }
                }
            )).font(.caption).toggleStyle(.checkbox)
            buttons
        }
    }

    private var buttons: some View {
        HStack {
            Button("Refresh") { model.refresh() }
            Button("Copy diagnostics") { model.copyDiagnostics() }
            Spacer()
            if let t = model.snapshot?.timestamp {
                Text(t.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
