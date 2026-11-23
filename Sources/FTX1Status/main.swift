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

// One menu bar icon is enough. LaunchServices only dedupes a single copy of the app, so a second
// copy (say ~/Applications from build-app.sh and /Applications from Homebrew) would otherwise run too.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id)
       .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    exit(0)
}

FTX1StatusApp.main()
