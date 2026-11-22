import Foundation
import IOKit.hid

struct DeviceBattery { let index: UInt8; let name: String; let percent: Int; let charging: Bool }

/// Talks HID++ 2.0 to Logitech devices behind a Bolt/Unifying receiver or over Bluetooth.
final class HIDPP {
    private var device: IOHIDDevice
    private let inBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)  // stable address for IOKit
    private var pending: [UInt8]? = nil
    private var waitingFor: (UInt8, UInt8, UInt8)? = nil // (devIndex, featureIndex, fn<<4|swid)
    private let swid: UInt8 = 0x07   // uncommon tag so Options+ replies aren't mistaken for ours

    init(device: IOHIDDevice) {
        self.device = device
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inBuf, 64, { ctx, _, _, _, _, report, len in
            let me = Unmanaged<HIDPP>.fromOpaque(ctx!).takeUnretainedValue()
            me.handle(Array(UnsafeBufferPointer(start: report, count: len)))
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceRegisterInputReportCallback(device, inBuf, 64, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        inBuf.deallocate()
    }

    /// Root ping: wakes a sleeping device so the following requests get clean answers.
    func ping(_ dev: UInt8) -> Bool { request(dev, 0x00, 1, [0, 0, 0x5A], timeout: 1.5) != nil }

    private func handle(_ r: [UInt8]) { if debug { print("in", r.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")) }
        guard r.count >= 4, r[0] == 0x11 || r[0] == 0x10, let (d, f, fs) = waitingFor, r[1] == d else { return }
        if (r[2] == 0xFF || r[2] == 0x8F), r.count > 4, r[3] == f, r[4] == fs { pending = []; return }         // error reply
        if r[2] == f && r[3] == fs { pending = Array(r[4...]) }
    }

    /// Sends a long HID++ request and waits for the matching reply.
    func request(_ dev: UInt8, _ feat: UInt8, _ fn: UInt8, _ params: [UInt8] = [], timeout: Double = 1.0) -> [UInt8]? {
        var msg = [UInt8](repeating: 0, count: 20)
        msg[0] = 0x11; msg[1] = dev; msg[2] = feat; msg[3] = (fn << 4) | swid
        for (i, p) in params.prefix(16).enumerated() { msg[4 + i] = p }
        pending = nil; waitingFor = (dev, feat, msg[3])
        let rc = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(msg[0]), msg, msg.count)
        if debug && rc != kIOReturnSuccess { print("setReport", String(rc, radix: 16)) }; guard rc == kIOReturnSuccess else { return nil }
        let end = Date().addingTimeInterval(timeout)
        while pending == nil && Date() < end { CFRunLoopRunInMode(.defaultMode, 0.02, true) }
        waitingFor = nil
        if let p = pending, !p.isEmpty { return p }
        return nil
    }

    func featureIndex(_ dev: UInt8, _ id: UInt16) -> UInt8? {
        guard let r = request(dev, 0x00, 0, [UInt8(id >> 8), UInt8(id & 0xFF)]), r[0] != 0 else { return nil }
        return r[0]
    }

    func name(_ dev: UInt8) -> String? {
        guard let f = featureIndex(dev, 0x0005), let c = request(dev, f, 0) else { return nil }
        let len = Int(c[0]); var bytes: [UInt8] = []
        while bytes.count < len, let chunk = request(dev, f, 1, [UInt8(bytes.count)]) {
            bytes += chunk.prefix(len - bytes.count)
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// UNIFIED_BATTERY get_status, accepted only if it looks like a real status reply
    /// (exactly one level flag set: 1 critical, 2 low, 4 good, 8 full; percent 0...100).
    private func unifiedStatus(_ dev: UInt8, _ f: UInt8) -> (Int, Bool)? {
        guard let r = request(dev, f, 1), r[0] <= 100, [1, 2, 4, 8].contains(r[1]), r[2] <= 3 else { return nil }
        return (Int(r[0]), r[2] == 1 || r[2] == 2)
    }

    func battery(_ dev: UInt8) -> (Int, Bool)? {
        if let f = featureIndex(dev, 0x1004) {
            // Read until two consecutive valid readings agree.
            var last: (Int, Bool)? = nil
            for _ in 0..<4 {
                guard let s = unifiedStatus(dev, f) else { continue }
                if let l = last, l == s { return s }
                last = s
            }
            return nil
        }
        if let f = featureIndex(dev, 0x1000), let r = request(dev, f, 0) {          // BATTERY_STATUS
            return (Int(r[0]), r[2] == 1 || r[2] == 2)
        }
        return nil
    }
}

enum LogiScanner {
    /// Finds Logitech HID++ interfaces (vendor usage page 0xFF00, usage 2 = long reports).
    static func scan() -> [DeviceBattery] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0x046D, kIOHIDPrimaryUsagePageKey: 0xFF00] as CFDictionary)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return [] }
        var out: [DeviceBattery] = []
        for dev in set {
            let orc = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)); if debug { print("open", String(orc, radix: 16), IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) ?? "") }; guard orc == kIOReturnSuccess else { continue }
            let h = HIDPP(device: dev)
            let transport = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? ""
            let indices: [UInt8] = transport == "USB" ? [1, 2, 3, 4, 5, 6] : [0xFF]
            for i in indices {
                guard h.ping(i), let (pct, chg) = h.battery(i) else { continue }
                let nm = h.name(i) ?? (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "Device \(i)")
                out.append(DeviceBattery(index: i, name: nm, percent: pct, charging: chg))
            }
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        return out.sorted { $0.name < $1.name }
    }
}
var debug = ProcessInfo.processInfo.environment["LOGI_DEBUG"] != nil
