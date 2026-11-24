import Foundation
import Testing
@testable import FTX1Core

struct EvaluateTests {
    // Port layout observed 2026-11-22: SLAB names landed in reverse order.
    func radioPorts() -> [SerialPort] {
        func p(_ path: String, _ driver: String, _ iface: Int) -> SerialPort {
            SerialPort(path: path, dialinPath: path.replacingOccurrences(of: "/dev/cu.", with: "/dev/tty."),
                       driver: driver, interfaceNumber: iface, usbSerial: "ABCD1234",
                       vendorID: radioBridgeVendorID, productID: radioBridgeProductID)
        }
        return [
            p("/dev/cu.usbserial-ABCD12340", "Apple", 0),
            p("/dev/cu.SLAB_USBtoUART5", "Silicon Labs", 0),
            p("/dev/cu.usbserial-ABCD12341", "Apple", 1),
            p("/dev/cu.SLAB_USBtoUART", "Silicon Labs", 1),
        ]
    }

    let reading = CATReading(baud: 38400, radioID: "0840", frequencyHz: 14_074_000, mode: "DATA-U")

    func snap(port: String, baud: Int, holders: [String: [String]] = [:], running: Bool = true,
              cat: CATResult? = nil, ports: [SerialPort]? = nil) -> Snapshot {
        Snapshot(ports: ports ?? radioPorts(), holders: holders, wsjtxRunning: running,
                 config: WSJTXConfig(rig: "Yaesu FTX-1", port: port, baud: baud, soundIn: "USB Audio Device",
                                     soundOut: "USB Audio Device"),
                 cat: cat ?? .ok(reading), lastGoodBaud: nil, audioDevices: ["USB Audio Device"])
    }

    func check(_ r: Report, _ title: String) -> Check? { r.checks.first { $0.title == title } }

    @Test func testTodaysFailure_wrongSLABPortAndBaud() {
        let r = evaluate(snap(port: "/dev/cu.SLAB_USBtoUART", baud: 4800,
                              holders: ["/dev/cu.SLAB_USBtoUART": ["wsjtx"]]))
        #expect(r.level == .error)
        #expect(check(r, "WSJT-X port")?.level == .error)
        #expect(check(r, "WSJT-X port")!.detail.contains("PTT"))
        #expect(check(r, "WSJT-X baud")?.level == .error)
        #expect(check(r, "WSJT-X link")?.level == .error)
        #expect(r.suggestedFix == ConfigFix(port: "/dev/cu.usbserial-ABCD12340", baud: 38400))
    }

    @Test func testHealthy() {
        let r = evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400,
                              holders: ["/dev/cu.usbserial-ABCD12340": ["wsjtx"]],
                              cat: .skipped("in use by wsjtx")).with(lastGoodBaud: 38400))
        #expect(r.level == .info)
        #expect(r.headline == "All good")
        #expect(r.suggestedFix == nil)
    }

    @Test func testSLABOnCATIsFragileWarning() {
        let r = evaluate(snap(port: "/dev/cu.SLAB_USBtoUART5", baud: 38400,
                              holders: ["/dev/cu.SLAB_USBtoUART5": ["wsjtx"]],
                              cat: .skipped("in use")).with(lastGoodBaud: 38400))
        #expect(r.level == .warn)
        #expect(r.suggestedFix?.port == "/dev/cu.usbserial-ABCD12340")
    }

    @Test func testRadioOff() {
        let r = evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400, cat: .skipped("none"), ports: []))
        #expect(r.level == .error)
        #expect(r.headline.contains("no CP2105"))
    }

    @Test func testOtherAppHoldingCATPort() {
        let r = evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400,
                              holders: ["/dev/cu.SLAB_USBtoUART5": ["rigctld"]], cat: .skipped("in use")))
        #expect(check(r, "WSJT-X link")?.level == .warn)
        #expect(check(r, "WSJT-X link")!.detail.contains("rigctld"))
    }

    @Test func testMissingAudioDevice() {
        var s = snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400)
        s.audioDevices = []
        #expect(check(evaluate(s), "Audio in")?.level == .error)
    }

    @Test func testSLABOnlyIsInfoAndFixKeepsPort() {
        // Only the Silicon Labs driver is loaded, so there's no usbserial- name to move to.
        let slabOnly = radioPorts().filter { !$0.hasStableName }
        let r = evaluate(snap(port: "/dev/cu.SLAB_USBtoUART5", baud: 4800, running: false, ports: slabOnly))
        #expect(check(r, "WSJT-X port")?.level == .info)
        #expect(r.suggestedFix == ConfigFix(port: "/dev/cu.SLAB_USBtoUART5", baud: 38400))
    }

    @Test func testSLABOnlyWrongPortSuggestsCATName() {
        let slabOnly = radioPorts().filter { !$0.hasStableName }
        let r = evaluate(snap(port: "/dev/cu.SLAB_USBtoUART", baud: 38400, running: false, ports: slabOnly))
        #expect(check(r, "WSJT-X port")?.level == .error)
        #expect(r.suggestedFix == ConfigFix(port: "/dev/cu.SLAB_USBtoUART5", baud: 38400))
    }

    @Test func testRememberedBaudMismatchIsOnlyAWarning() {
        // WSJT-X is running but hasn't opened the port, so we only have the remembered rate.
        let r = evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 4800,
                              cat: .skipped("WSJT-X is running")).with(lastGoodBaud: 38400))
        #expect(check(r, "WSJT-X baud")?.level == .warn)
        #expect(check(r, "WSJT-X baud")!.detail.contains("last answered"))
        #expect(r.suggestedFix == nil)  // never write a remembered rate over WSJT-X's
    }

    @Test func testWSJTXHoldingPortTrustsItsBaud() {
        // WSJT-X is connected at 4800; a stale remembered 38400 mustn't keep the icon yellow.
        let r = evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 4800,
                              holders: ["/dev/cu.usbserial-ABCD12340": ["wsjtx"]],
                              cat: .skipped("in use")).with(lastGoodBaud: 38400))
        #expect(check(r, "WSJT-X baud")?.level == .info)
        #expect(r.level <= .info)
        #expect(r.suggestedFix == nil)
    }

    @Test func testFixKeepsConfiguredBaudWhenNotLive() {
        // rigctld holds the port, so no probe; WSJT-X is on a SLAB name at 4800, remembered rate 38400.
        let r = evaluate(snap(port: "/dev/cu.SLAB_USBtoUART5", baud: 4800,
                              holders: ["/dev/cu.usbserial-ABCD12340": ["rigctld"]], running: false,
                              cat: .skipped("in use")).with(lastGoodBaud: 38400))
        #expect(r.suggestedFix == ConfigFix(port: "/dev/cu.usbserial-ABCD12340", baud: 4800))
    }

    @Test func testTTYNameIsTheSamePort() {
        let tty = "/dev/tty.usbserial-ABCD12340"
        let r = evaluate(snap(port: tty, baud: 38400, holders: [tty: ["wsjtx"]]))
        #expect(check(r, "WSJT-X port")?.level == .ok)
        #expect(check(r, "WSJT-X link")?.level == .ok)
        #expect(r.suggestedFix == nil)
    }

    @Test func testTTYHolderCountsAsCATHolder() {
        let s = snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400,
                     holders: ["/dev/tty.SLAB_USBtoUART5": ["flrig"]])
        #expect(s.catHolders == ["flrig"])
    }

    @Test func testRigServerSetupIsFine() {
        var s = snap(port: "", baud: 4800, holders: ["/dev/cu.usbserial-ABCD12340": ["flrig"]],
                     cat: .skipped("in use by flrig"))
        s.config?.rig = "FLRig FLRig"
        s.config?.port = nil
        let r = evaluate(s.with(lastGoodBaud: 38400))
        #expect(r.level <= .info, "\(r.checks)")
        #expect(check(r, "WSJT-X link")?.level == .ok)
        #expect(check(r, "WSJT-X port") == nil)
        #expect(r.suggestedFix == nil)
    }

    @Test func testRadioOffIsMarkedDisconnected() {
        let r = evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400, cat: .skipped("none"), ports: []))
        #expect(!r.radioConnected)
        #expect(evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400)).radioConnected)
    }

    @Test func testNoCATReply() {
        let r = evaluate(snap(port: "/dev/cu.usbserial-ABCD12340", baud: 38400, running: false,
                              cat: .noReply(triedBauds: [38400, 4800])))
        #expect(check(r, "CAT reply")?.level == .error)
    }
}

struct ParsingTests {
    let ini = """
    [Configuration]
    CATSerialPort=/dev/cu.SLAB_USBtoUART
    CATSerialRate=4800
    PTTMethod=@Variant(\\0\\0\\0\\x7f\\0\\0\\0\\x1eTransceiverFactory::PTTMethod\\0\\0\\0\\0\\xfPTT_method_CAT\\0)
    Rig=Yaesu FTX-1
    SoundInName=USB Audio Device
    SoundOutName=USB Audio Device
    """

    @Test func testParseINI() {
        let c = WSJTXConfigFile.parse(ini)
        #expect(c.port == "/dev/cu.SLAB_USBtoUART")
        #expect(c.baud == 4800)
        #expect(c.rig == "Yaesu FTX-1")
        #expect(c.pttMethod == "PTT_method_CAT")
        #expect(c.soundIn == "USB Audio Device")
    }

    @Test func testRewriteINI() {
        let out = WSJTXConfigFile.rewrite(ini, ConfigFix(port: "/dev/cu.usbserial-ABCD12340", baud: 38400))
        let c = WSJTXConfigFile.parse(out)
        #expect(c.port == "/dev/cu.usbserial-ABCD12340")
        #expect(c.baud == 38400)
        #expect(c.rig == "Yaesu FTX-1")
    }

    @Test func testParseOnlyReadsConfigurationSection() {
        let text = """
        [Common]
        Rig=Some Other Rig
        [Configuration]
        CATSerialPort=/dev/cu.usbserial-ABCD12340
        Rig=Yaesu FTX-1
        [MultiSettings]
        FT8\\Configuration\\CATSerialPort=/dev/cu.SLAB_USBtoUART
        """
        let c = WSJTXConfigFile.parse(text)
        #expect(c.rig == "Yaesu FTX-1")
        #expect(c.port == "/dev/cu.usbserial-ABCD12340")
    }

    @Test func testParseQuotedAndEscapedNames() {
        // QSettings quotes values with commas or edge spaces, and escapes non-ASCII as \xHHHH.
        let text = #"""
        [Configuration]
        SoundInName="USB Audio CODEC, 2ch"
        SoundOutName=Ben\x2019s AirPods
        Rig=@@odd
        """#
        let c = WSJTXConfigFile.parse(text)
        #expect(c.soundIn == "USB Audio CODEC, 2ch")
        #expect(c.soundOut == "Ben\u{2019}s AirPods")
        #expect(c.rig == "@odd")
    }

    @Test func testQtEscapes() {
        #expect(WSJTXConfigFile.decodeQtEscapes(#"a\tb\\c\"d"#) == "a\tb\\c\"d")
        #expect(WSJTXConfigFile.decodeQtEscapes(#"\x41\x42\x43!"#) == "ABC!")
        #expect(WSJTXConfigFile.decodeQtEscapes(#"\x42C"#) == "\u{42C}")  // hex is greedy, so Qt escapes a following C
        #expect(WSJTXConfigFile.decodeQtEscapes(#"\101"#) == "A")         // octal
    }

    @Test func testRewriteOnlyTouchesConfigurationSection() {
        let text = """
        [MultiSettings]
        CATSerialPort=/dev/other
        [Configuration]
        CATSerialPort=/dev/cu.SLAB_USBtoUART
        CATSerialRate=4800
        """
        let out = WSJTXConfigFile.rewrite(text, ConfigFix(port: "/dev/cu.usbserial-ABCD12340", baud: 38400))
        #expect(out.contains("[MultiSettings]\nCATSerialPort=/dev/other\n"))
        #expect(WSJTXConfigFile.parse(out).port == "/dev/cu.usbserial-ABCD12340")
    }

    @Test func testRewriteAddsMissingKeys() {
        let fix = ConfigFix(port: "/dev/cu.usbserial-ABCD12340", baud: 38400)
        let text = "[Configuration]\nRig=Yaesu FTX-1\n\n[Other]\nX=1\n"
        let out = WSJTXConfigFile.rewrite(text, fix)
        #expect(out == "[Configuration]\nRig=Yaesu FTX-1\nCATSerialPort=/dev/cu.usbserial-ABCD12340\nCATSerialRate=38400\n\n[Other]\nX=1\n")

        let noSection = WSJTXConfigFile.rewrite("[General]\nA=1\n", fix)
        #expect(WSJTXConfigFile.parse(noSection).port == fix.port)
        #expect(WSJTXConfigFile.parse(noSection).baud == 38400)
    }

    @Test func testApplyWritesBackupAndVerifies() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("WSJT-X.ini")
        try ini.write(to: url, atomically: true, encoding: .utf8)
        let backup = try WSJTXConfigFile.apply(ConfigFix(port: "/dev/cu.usbserial-ABCD12340", baud: 38400), to: url)
        #expect(try String(contentsOf: backup, encoding: .utf8) == ini)
        #expect(WSJTXConfigFile.load(from: url)?.baud == 38400)
    }

    @Test func testApplyKeepsPermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("WSJT-X.ini")
        try ini.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try WSJTXConfigFile.apply(ConfigFix(port: "/dev/cu.usbserial-ABCD12340", baud: 38400), to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func testProbeStopsBeforeOpening() {
        // The stop check runs before each baud, so nothing is opened (the path doesn't even exist).
        let r = CATProbe.run(path: "/dev/cu.does-not-exist", preferred: nil, stopReason: { "WSJT-X started" })
        #expect(r == .skipped("WSJT-X started"))
    }

    @Test func testLsofParse() {
        let h = PortHolders.parse("p17230\ncwsjtx\nf20\nn/dev/cu.SLAB_USBtoUART\n")
        #expect(h == ["/dev/cu.SLAB_USBtoUART": ["wsjtx"]])
    }

    @Test func testCATParse() {
        #expect(CATProbe.extract("FA014074000;", prefix: "FA") == "014074000")
        #expect(CATProbe.extract("MD0C;", prefix: "MD0") == "C")
        #expect(CATProbe.modeName("C") == "DATA-U")
    }

    @Test func testCATParseToleratesNoiseAndAutoInfo() {
        // Auto Information mode can push an FA update ahead of the reply we asked for.
        #expect(CATProbe.extract("FA014074000;ID0840;", prefix: "ID") == "0840")
        #expect(CATProbe.extract("\u{0}\u{FF}ID0840;", prefix: "ID") == "0840")
        #expect(CATProbe.extract("ID08", prefix: "ID") == nil)        // incomplete
        #expect(CATProbe.extract("FA014074000;", prefix: "ID") == nil)
    }
}

extension Snapshot {
    func with(lastGoodBaud: Int?) -> Snapshot { var s = self; s.lastGoodBaud = lastGoodBaud; return s }
}
