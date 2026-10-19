import AppKit

setlinebuf(stdout)
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // Dock'ta görünmez; menü çubuğu simgesiyle yönetilir
    app.run()
}
