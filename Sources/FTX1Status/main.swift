import AppKit
import FTX1Core

// `FTX1Status --dump` prints the same diagnostics the menu shows, then exits.
if CommandLine.arguments.contains("--dump") {
    let lastGood = UserDefaults.standard.object(forKey: "lastGoodBaud") as? Int
    let snap = StatusModel.collect(lastGoodBaud: lastGood, wsjtxRunning: StatusModel.isWSJTXRunning())
    print(diagnosticsText(snap.snapshot, evaluate(snap.snapshot)))
    exit(0)
}

FTX1StatusApp.main()
