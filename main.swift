import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var known: [String: (DeviceBattery, Date)] = [:]   // last reading per device name
    var timer: Timer?
    let queue = DispatchQueue(label: "logi.scan")
    var scanning = false

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.title = "…"
        let menu = NSMenu(); menu.delegate = self
        item.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
        }
        // Turn on Open at Login the first time the app runs; after that, respect the user's choice.
        let key = "loginItemConfigured"
        if !UserDefaults.standard.bool(forKey: key) {
            do { try SMAppService.mainApp.register() } catch { NSLog("Login item register failed: \(error)") }
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    private func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("key") || n.contains("craft") { return "keyboard" }
        if n.contains("master") || n.contains("anywhere") || n.contains("mouse") || n.contains("lift") || n.contains("ergo") { return "computermouse" }
        if n.contains("headset") || n.contains("zone") { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }
    private func color(_ p: Int) -> NSColor? { p <= 15 ? .systemRed : p <= 30 ? .systemOrange : nil }

    var devices: [DeviceBattery] { known.values.map { $0.0 }.sorted { $0.name < $1.name } }

    func render() {
        guard let button = item.button else { return }
        let devs = devices
        if devs.isEmpty { button.attributedTitle = NSAttributedString(string: "Logi –"); return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let s = NSMutableAttributedString()
        for (i, d) in devs.enumerated() {
            if i > 0 { s.append(NSAttributedString(string: "  ")) }
            if let img = NSImage(systemSymbolName: symbol(for: d.name), accessibilityDescription: d.name) {
                img.isTemplate = true
                let att = NSTextAttachment(); att.image = img
                let h = font.capHeight + 3
                att.bounds = NSRect(x: 0, y: -2, width: img.size.width * h / img.size.height, height: h)
                s.append(NSAttributedString(attachment: att))
                s.append(NSAttributedString(string: " "))
            }
            var a: [NSAttributedString.Key: Any] = [.font: font]
            if let c = color(d.percent), !d.charging { a[.foregroundColor] = c }
            s.append(NSAttributedString(string: "\(d.percent)%" + (d.charging ? "⚡︎" : ""), attributes: a))
        }
        button.attributedTitle = s
        button.toolTip = devs.map { "\($0.name): \($0.percent)%" }.joined(separator: "\n")
    }

    @objc func refresh() {
        guard !scanning else { return }
        scanning = true
        queue.async {
            var found = LogiScanner.scan()
            if found.count < self.known.count { Thread.sleep(forTimeInterval: 1); found = LogiScanner.scan() } // wake sleepy devices
            DispatchQueue.main.async {
                for d in found { self.known[d.name] = (d, Date()) }
                self.scanning = false
                self.render()
            }
        }
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let f = DateFormatter(); f.timeStyle = .short
        if known.isEmpty {
            let it = NSMenuItem(title: "No Logitech devices found", action: nil, keyEquivalent: ""); it.isEnabled = false; m.addItem(it)
        }
        for (d, t) in known.values.sorted(by: { $0.0.name < $1.0.name }) {
            let it = NSMenuItem(title: "\(d.name) — \(d.percent)%\(d.charging ? " (charging)" : "")", action: nil, keyEquivalent: "")
            it.image = NSImage(systemSymbolName: symbol(for: d.name), accessibilityDescription: nil)
            it.toolTip = "Read at \(f.string(from: t))"
            it.isEnabled = false
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r").target = self
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        let status = SMAppService.mainApp.status
        login.state = status == .enabled ? .on : .off
        m.addItem(login)
        if status == .requiresApproval {
            let approve = NSMenuItem(title: "Allow Open at Login in System Settings…", action: #selector(openLoginSettings), keyEquivalent: "")
            approve.target = self
            m.addItem(approve)
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("Login item error: \(error)") }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
