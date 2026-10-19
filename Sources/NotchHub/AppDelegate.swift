import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = HubModel()
    private var server: HubServer!
    private var windows: [NotchWindowController] = []
    private var statusItem: NSStatusItem!
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private var bag: Set<AnyCancellable> = []

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
        installMainMenu()

        // Ayar değişince pencereleri yeniden ölç (aynı döngüdeki değişiklikler tek seferde uygulanır).
        Settings.shared.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &bag)

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
        // settings:<sekme>[:<png yolu>] — ayarlar penceresini o sekmede açar, isteğe bağlı görüntüsünü yazar.
        if cmd.hasPrefix("settings:") {
            let parts = cmd.dropFirst("settings:".count).split(separator: ":", maxSplits: 1).map(String.init)
            settingsWindow.show(tab: parts.first.flatMap(SettingsTab.init(rawValue:)))
            if parts.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.settingsWindow.snapshot(to: parts[1]) }
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

    /// Çentikli ekranlar her zaman; çentiksiz olanlar yalnızca ada ayarı açıkken.
    private var wantedScreens: [NSScreen] {
        NSScreen.screens.filter { Settings.shared.showIsland || NotchGeometry.make(for: $0).style == .notch }
    }

    @objc private func screensChanged() {
        // Ekran eklenip çıkarıldıysa pencereleri baştan kur; yalnızca ölçüler değiştiyse tazele.
        let wanted = wantedScreens
        if wanted.count != windows.count || zip(wanted, windows).contains(where: { $0 !== $1.screen }) {
            rebuildWindows()
        } else {
            windows.forEach { $0.refreshGeometry() }
        }
    }

    private func rebuildWindows() {
        windows.forEach { $0.invalidate() }
        windows = wantedScreens.map { NotchWindowController(screen: $0, model: model) }
    }

    // MARK: - Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let counts = Dictionary(grouping: model.entries, by: { $0.client.id }).mapValues(\.count)
        if model.clients.isEmpty {
            menu.addItem(disabled("Bağlı uygulama yok"))
        } else {
            menu.addItem(disabled("Çentikteki uygulamalar"))
            for c in model.clients.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
                let n = counts[c.id] ?? 0
                let hidden = Settings.shared.isHidden(c.id) ? " (gizli)" : ""
                menu.addItem(disabled("  \(c.name) — \(n) etkinlik\(hidden)"))
            }
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "NotchHub'dan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openSettings() { settingsWindow.show() }

    /// Dock'ta görünmeyen uygulamada da ayarlar penceresi öndeyken ⌘, ⌘W ve ⌘Q çalışsın.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let settings = NSMenuItem(title: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        app.addItem(settings)
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Pencereyi Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        app.addItem(NSMenuItem(title: "NotchHub'dan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = app
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }
}
