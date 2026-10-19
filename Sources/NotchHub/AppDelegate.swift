import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = HubModel()
    private var server: HubServer!
    private var windows: [NotchWindowController] = []
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = HubServer(model: model)
        do {
            try server.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "NotchHub başlatılamadı"
            alert.informativeText = "Soket açılamadı: \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
        }

        rebuildWindows()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.portrait.tophalf.filled",
                                           accessibilityDescription: "NotchHub")
            ?? NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchHub")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if ProcessInfo.processInfo.environment["NOTCH_DEBUG"] != nil {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(debugCommand(_:)), name: .init("local.mainai.notchhub.debug"), object: nil)
        }
    }

    /// Hata ayıklama: `open`, `close`, `snapshot:<klasör>` (ekran başına bir PNG).
    @objc private func debugCommand(_ n: Notification) {
        guard let cmd = n.object as? String else { return }
        if cmd == "open" { windows.forEach { $0.setExpanded(true, pinned: true) } }
        if cmd == "close" { windows.forEach { $0.setExpanded(false) } }
        // tap:<istemci>/<etkinlik>/<eylem> — bir düğmeye basılmış gibi olay gönderir.
        if cmd.hasPrefix("tap:") {
            let parts = cmd.dropFirst(4).split(separator: "/").map(String.init)
            if parts.count == 3, let e = model.entries.first(where: { $0.id == "\(parts[0])/\(parts[1])" }) {
                model.send(e, action: parts[2])
            }
        }
        if cmd.hasPrefix("snapshot:") {
            let dir = String(cmd.dropFirst("snapshot:".count))
            for (i, w) in windows.enumerated() {
                print("[hub] ekran \(i): \(w.debugSnapshot(to: "\(dir)/notch-\(i).png"))")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }

    // MARK: - Ekranlar

    @objc private func screensChanged() {
        // Ekran eklenip çıkarıldıysa pencereleri baştan kur; yalnızca çözünürlük değiştiyse ölçüleri tazele.
        let current = NSScreen.screens
        if current.count != windows.count || zip(current, windows).contains(where: { $0 !== $1.screen }) {
            rebuildWindows()
        } else {
            windows.forEach { $0.refreshGeometry() }
        }
    }

    private func rebuildWindows() {
        windows.forEach { $0.invalidate() }
        windows = NSScreen.screens.map { NotchWindowController(screen: $0, model: model) }
    }

    // MARK: - Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clients = Dictionary(grouping: model.entries, by: { $0.client.name })
        if clients.isEmpty {
            menu.addItem(disabled("Bağlı uygulama yok"))
        } else {
            menu.addItem(disabled("Çentikteki uygulamalar"))
            for (name, entries) in clients.sorted(by: { $0.key < $1.key }) {
                menu.addItem(disabled("  \(name) — \(entries.count) etkinlik"))
            }
        }
        menu.addItem(.separator())

        let header = disabled("Çentik açılsın:")
        menu.addItem(header)
        for (mode, title) in [(OpenMode.hover, "Üzerine gelince"), (.click, "Tıklayınca")] {
            let i = NSMenuItem(title: "  " + title, action: #selector(setMode(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = mode.rawValue
            i.state = OpenMode.current == mode ? .on : .off
            menu.addItem(i)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Oturum Açılışında Başlat", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "NotchHub'dan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = OpenMode(rawValue: raw) else { return }
        OpenMode.current = m
        windows.forEach { $0.setExpanded(false) }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Oturum açılışı ayarı değiştirilemedi"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }
}
