import Testing
@testable import FTX1Core

struct EvaluateTests {
    // Port layout observed 2026-11-22: SLAB names landed in reverse order.
    func radioPorts() -> [SerialPort] {
        func p(_ path: String, _ driver: String, _ iface: Int) -> SerialPort {
            SerialPort(path: path, driver: driver, interfaceNumber: iface, usbSerial: "ABCD1234",
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
        #expect(r.headline.contains("No CP2105"))
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

    @Test func testLsofParse() {
        let h = PortHolders.parse("p17230\ncwsjtx\nf20\nn/dev/cu.SLAB_USBtoUART\n")
        #expect(h == ["/dev/cu.SLAB_USBtoUART": ["wsjtx"]])
    }

    @Test func testCATParse() {
        #expect(CATProbe.parse("FA014074000;", prefix: "FA") == "014074000")
        #expect(CATProbe.modeName("C") == "DATA-U")
    }
}

extension Snapshot {
    func with(lastGoodBaud: Int?) -> Snapshot { var s = self; s.lastGoodBaud = lastGoodBaud; return s }
}
