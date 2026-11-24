import AppKit
import FTX1Core

let args = CommandLine.arguments.dropFirst()

if args.contains("--help") || args.contains("-h") {
    print("""
    usage: FTX1Status [--dump | --version]
      --dump      print the diagnostics the menu shows, then exit
      --version   print the app version
    With no arguments, runs the menu bar app.
    """)
    exit(0)
}

if args.contains("--version") {
    print(StatusModel.appVersion ?? "dev build")
    exit(0)
}

// `FTX1Status --dump` prints the same diagnostics the menu shows, then exits.
if args.contains("--dump") {
    let lastGood = UserDefaults.standard.object(forKey: "lastGoodBaud") as? Int
    let snap = StatusModel.collect(lastGoodBaud: lastGood, wsjtxRunning: StatusModel.isWSJTXRunning())
    print(diagnosticsText(snap.snapshot, evaluate(snap.snapshot), appVersion: StatusModel.appVersion))
    exit(0)
}

// One menu bar icon is enough. LaunchServices only dedupes a single copy of the app, so another
// copy (an older version, or ~/Applications from build-app.sh next to /Applications from Homebrew)
// could be running. The copy launched last wins: it's usually the one just installed.
let ids = Set([Bundle.main.bundleIdentifier, StatusModel.legacyBundleID].compactMap { $0 })
let others = ids.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    others.forEach { $0.terminate() }
    let deadline = Date().addingTimeInterval(3)
    while others.contains(where: { !$0.isTerminated }), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    // If an old copy won't quit, don't put a second icon next to it.
    if others.contains(where: { !$0.isTerminated }) { exit(0) }
}

FTX1StatusApp.main()
