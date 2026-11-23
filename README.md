# FTX1 Status

A macOS menu bar app that checks why WSJT-X can't reach a Yaesu FTX-1, refreshing every 5 seconds.

## What it checks

- **Radio on USB**: the FTX-1's CP2105 USB-serial chip (10C4:EA70).
- **CAT port**: which `/dev/cu.*` names map to interface 0 (Enhanced, CAT) and which to interface 1 (Standard, PTT). It also shows which driver owns each name.
- **CAT reply**: sends read-only queries (`ID;`, `FA;`, `MD0;`) and auto-detects the baud rate. It skips this while another app has the port open.
- **WSJT-X.ini**: checks that the configured port is the CAT interface, the baud rate matches the radio, and the configured audio devices are present.
- **WSJT-X link**: whether WSJT-X, or something else, has the CAT port open.

## Why the port keeps "disappearing"

The CP2105 has two serial ports, and two drivers attach to both of them:

- **Apple's driver** names them `cu.usbserial-<USB serial number><n>`. These names stay the same across reboots.
- **The Silicon Labs driver** names them `cu.SLAB_USBtoUART`, `cu.SLAB_USBtoUART5`, and so on, in enumeration order. That order changes with power-on order.

When WSJT-X is pointed at a `SLAB_*` name, it will sometimes end up on the PTT port. Use `/dev/cu.usbserial-…0` at the radio's CAT rate (38400 on this rig).

## Install

    brew install --cask evil-wizard-corp/tap/ftx1-status

Or download the zip from [Releases](https://github.com/evil-wizard-corp/ftx1-status/releases). The app isn't notarized, because there's no paid Apple Developer account. The Homebrew cask clears the quarantine flag for you. If you install from the zip and macOS blocks the app, run `xattr -dr com.apple.quarantine "/Applications/FTX1 Status.app"`, or use System Settings → Privacy & Security → Open Anyway.

## Build from source

    ./build-app.sh --install   # builds build/FTX1 Status.app and copies it to ~/Applications
    swift test                 # evaluation, parsing, and lsof tests

## Releasing

Push a tag like `v0.2.0`. The release workflow:

1. runs the tests
2. builds a universal (arm64 + x86_64) app
3. creates a GitHub release with the zip attached
4. bumps the cask in [evil-wizard-corp/homebrew-tap](https://github.com/evil-wizard-corp/homebrew-tap)

Tags with a hyphen, like `v0.2.0-beta.1`, become pre-releases and skip the cask bump.

Running `.build/debug/FTX1Status --dump` prints the same diagnostics in the terminal.

"Apply to WSJT-X.ini" rewrites `CATSerialPort` and `CATSerialRate`. It saves a timestamped backup first, and only runs while WSJT-X is closed, because WSJT-X overwrites the file when it quits.

## License

MIT — see [LICENSE](LICENSE).
