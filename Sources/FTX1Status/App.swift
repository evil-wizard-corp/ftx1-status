import SwiftUI
import FTX1Core

struct FTX1StatusApp: App {
    @StateObject private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: StatusIcon.image(for: model.report))
        }
        .menuBarExtraStyle(.window)
    }
}

enum StatusIcon {
    static func image(for report: Report?) -> NSImage {
        let description = report.map { "FTX1 Status: \($0.headline)" } ?? "FTX1 Status"
        let base = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: description)!
        guard let level = report?.level else { return templated(base) }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [level.color]))
        let img = base.withSymbolConfiguration(config) ?? base
        img.isTemplate = false
        return img
    }

    private static func templated(_ img: NSImage) -> NSImage { img.isTemplate = true; return img }
}

extension Level {
    var color: NSColor {
        switch self {
        case .ok: return .systemGreen
        case .info: return .systemGreen
        case .warn: return .systemYellow
        case .error: return .systemRed
        }
    }
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    var swiftUIColor: Color {
        self == .info ? .secondary : Color(nsColor: color)
    }
}
