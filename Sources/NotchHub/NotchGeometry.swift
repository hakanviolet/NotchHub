import AppKit
import NotchKit

/// Bir ekrandaki çentik ya da Dynamic Island'ın konumu ve ölçüleri.
struct NotchGeometry: Equatable {
    enum Style { case notch, island }

    let style: Style
    /// Ekranın tepesi ve çentiğin yatay merkezi (genel ekran koordinatları).
    let top: CGFloat
    let centerX: CGFloat
    /// Fiziksel çentik (ya da kapalı adanın) ölçüsü.
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// Ada stilinde ekranın tepesinden boşluk.
    let topInset: CGFloat
    /// Ayarlardan gelen yerleşim (ekrana sığacak şekilde sınırlanmış).
    var maxCards = 3
    var cardWidth: CGFloat = 300

    @MainActor static func make(for screen: NSScreen) -> NotchGeometry {
        var g = shape(for: screen)
        let s = Settings.shared
        g.cardWidth = s.cardWidth.points
        // Açık hâl ekranın kenarlarına taşmasın.
        let fit = Int((screen.frame.width - 24 - 80 + cardSpacing) / (g.cardWidth + cardSpacing))
        g.maxCards = max(1, min(s.maxCards, fit))
        return g
    }

    @MainActor private static func shape(for screen: NSScreen) -> NotchGeometry {
        let f = screen.frame
        let overlap = CGFloat(Settings.shared.notchOverlap)
        let forceIsland = ProcessInfo.processInfo.environment["NOTCH_FORCE_ISLAND"] != nil  // hata ayıklama
        if !forceIsland, screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            // Bu alanlar bazı sürümlerde ekrana göre, bazılarında genel koordinatta geliyor.
            let offset = abs(l.minX - f.minX) < 1 ? 0 : f.minX
            // Sistemin bildirdiği ölçü fiziksel çentikten bir tık küçük kalıyor; kenarlar görünmesin diye
            // biraz taşır (kullanıcı ekranında doğrulandı).
            return NotchGeometry(style: .notch, top: f.maxY, centerX: offset + (l.maxX + r.minX) / 2,
                                 notchWidth: r.minX - l.maxX + overlap * 2,
                                 notchHeight: screen.safeAreaInsets.top + overlap, topInset: 0)
        }
        // Çentik yok (harici ekran ya da çentiği gizleyen çözünürlük): menü çubuğunun ortasında ada.
        var bar = f.maxY - screen.visibleFrame.maxY
        if bar < 10 { bar = 24 }
        let h = max(bar - 4, 20)
        return NotchGeometry(style: .island, top: f.maxY, centerX: f.midX,
                             notchWidth: 0, notchHeight: h, topInset: (bar - h) / 2)
    }

    // MARK: - Yerleşim

    static let cardHeight: CGFloat = 132
    static let cardSpacing: CGFloat = 10

    /// Kapalıyken bir kanadın genişliği.
    var wing: CGFloat { notchHeight + 8 }

    /// Ada stilinde ortadaki boşluk (çentik olmadığı için başlık için yer).
    var islandMiddle: CGFloat { 90 }

    func closedSize(hasContent: Bool) -> CGSize {
        switch style {
        case .notch:
            return CGSize(width: notchWidth + (hasContent ? wing * 2 : 0), height: notchHeight)
        case .island:
            return hasContent ? CGSize(width: islandMiddle + wing * 2, height: notchHeight) : .zero
        }
    }

    func openSize(cards: Int) -> CGSize {
        let n = CGFloat(max(1, min(cards, maxCards)))
        let contentW = n * cardWidth + (n - 1) * Self.cardSpacing + 2 * 12
        let header: CGFloat = style == .notch ? notchHeight : 8
        let w = max(contentW, closedSize(hasContent: true).width)
        let h = cards == 0 ? header + 44 : header + Self.cardHeight + 12
        return CGSize(width: w, height: h)
    }

    /// Kapalıyken yandaki ikinci etkinlik baloncuğu.
    var bubbleSize: CGFloat { notchHeight }
    var bubbleGap: CGFloat { 6 }

    /// Pencerenin sabit çerçevesi: en büyük açık hâli + gölge payı.
    var windowFrame: NSRect {
        let size = openSize(cards: maxCards)
        let w = size.width + 80, h = size.height + topInset + 40
        return NSRect(x: centerX - w / 2, y: top - h, width: w, height: h)
    }

    /// Ekran koordinatlarında, tepeye ortalanmış dikdörtgen.
    func rect(_ size: CGSize) -> NSRect {
        NSRect(x: centerX - size.width / 2, y: top - topInset - size.height, width: size.width, height: size.height)
    }

    func bubbleRect(closedWidth: CGFloat) -> NSRect {
        NSRect(x: centerX + closedWidth / 2 + bubbleGap, y: top - topInset - bubbleSize,
               width: bubbleSize, height: bubbleSize)
    }
}

extension NotchTint {
    var color: NSColor {
        switch self {
        case .white: .white
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }
}
