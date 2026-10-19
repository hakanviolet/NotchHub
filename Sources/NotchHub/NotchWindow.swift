import AppKit
import Combine
import SwiftUI

enum OpenMode: String {
    case hover, click

    static var current: OpenMode {
        get { OpenMode(rawValue: UserDefaults.standard.string(forKey: "openMode") ?? "") ?? .hover }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "openMode") }
    }
}

/// Tek bir ekranın açık/kapalı durumu.
@MainActor
final class WindowState: ObservableObject {
    @Published var geometry: NotchGeometry
    /// Kullanıcı açtı (üzerine gelme ya da tıklama).
    @Published var expanded = false
    /// Bir etkinlik öne çıkarıldığı için kısa süre açık.
    @Published var peeking = false
    /// Kapalı şekle ya da baloncuğa tıklanınca.
    var onTapClosed: (() -> Void)?

    var isOpen: Bool { expanded || peeking }

    init(geometry: NotchGeometry) { self.geometry = geometry }
}

/// Ekran başına bir panel. Pencere sabit ve büyük; görünen şekil içinde SwiftUI ile canlanır.
/// Fare şeklin dışındayken pencere tıklamaları geçirir, böylece menü çubuğu ve alttaki pencereler çalışır.
@MainActor
final class NotchWindowController {
    let screen: NSScreen
    private let model: HubModel
    private let state: WindowState
    private let panel: NotchPanel
    private var timer: Timer?
    private var hoverSince: Date?
    private var leftSince: Date?
    private var clickMonitor: Any?
    private var bag: Set<AnyCancellable> = []

    init(screen: NSScreen, model: HubModel) {
        self.screen = screen
        self.model = model
        state = WindowState(geometry: .make(for: screen))
        panel = NotchPanel()
        state.onTapClosed = { [weak self] in self?.toggleFromClick() }

        let root = NotchRootView(model: model, state: state)
        let host = PassthroughHostingView(rootView: root)
        panel.contentView = host
        panel.setFrame(state.geometry.windowFrame, display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        // Tıklama kipinde dışarı tıklanınca kapat.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.expanded, !self.openRect.contains(NSEvent.mouseLocation) else { return }
                self.setExpanded(false)
            }
        }
        // Öne çıkarma (pulse) yalnızca bu ekran açık değilken kısa bir göz atma olarak görünür.
        model.$pulsing.sink { [weak self] p in
            guard let self else { return }
            withAnimation(Self.spring) { self.state.peeking = p != nil && !self.state.expanded }
        }.store(in: &bag)
    }

    func invalidate() {
        timer?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        panel.orderOut(nil)
    }

    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.8)

    // MARK: - Fare

    private var closedSize: CGSize { state.geometry.closedSize(hasContent: model.primary != nil) }

    /// Kapalıyken etkileşim alanı: şekil + varsa yan baloncuk + birkaç pt pay.
    private var closedRect: NSRect {
        let g = state.geometry
        var r = g.rect(closedSize)
        if g.style == .notch, model.primary == nil {
            r = g.rect(CGSize(width: g.notchWidth, height: g.notchHeight))
        }
        if model.secondary != nil { r = r.union(g.bubbleRect(closedWidth: closedSize.width)) }
        // Çentik ekranın tepesine yapışık; imleç en üst piksele gittiğinde de yakalansın.
        return r.insetBy(dx: -4, dy: -4)
    }

    private var openRect: NSRect {
        let n = state.peeking && !state.expanded ? 1 : model.entries.count
        return state.geometry.rect(state.geometry.openSize(cards: n)).insetBy(dx: -2, dy: -2)
    }

    private func track() {
        let p = NSEvent.mouseLocation
        let inClosed = closedRect.contains(p)
        let inOpen = openRect.contains(p)

        if OpenMode.current == .hover {
            if !state.expanded {
                if inClosed {
                    if hoverSince == nil { hoverSince = Date() }
                    if Date().timeIntervalSince(hoverSince!) > 0.12 { setExpanded(true) }
                } else {
                    hoverSince = nil
                }
            } else {
                if inOpen || inClosed {
                    leftSince = nil
                } else {
                    if leftSince == nil { leftSince = Date() }
                    if Date().timeIntervalSince(leftSince!) > 0.3 { setExpanded(false) }
                }
            }
        }
        let interactive = state.isOpen ? inOpen : inClosed
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    func setExpanded(_ open: Bool) {
        hoverSince = nil
        leftSince = nil
        guard state.expanded != open else { return }
        withAnimation(Self.spring) {
            state.expanded = open
            if open { state.peeking = false }
        }
    }

    /// Tıklama kipinde kapalı şekle tıklanınca (görünümden çağrılır).
    func toggleFromClick() { setExpanded(!state.expanded) }

    /// Hata ayıklama: görünen bölgenin PNG görüntüsü ve ölçüler.
    func debugSnapshot(to path: String) -> String {
        if let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        return "stil=\(state.geometry.style) açık=\(state.isOpen) pencere=\(panel.frame) kapalı=\(closedRect) açıkAlan=\(openRect)"
    }

    func refreshGeometry() {
        let g = NotchGeometry.make(for: screen)
        guard g != state.geometry else { return }
        state.geometry = g
        panel.setFrame(g.windowFrame, display: true)
    }
}

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // Menü çubuğunun (mainMenu) üstünde olmalı ki çentiğin yanlarını kaplayabilsin.
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PassthroughHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
