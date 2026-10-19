import AppKit
import NotchKit
import SwiftUI

/// Pencerenin kökü: tepeye ortalanmış tek şekil (+ kapalıyken yandaki baloncuk).
struct NotchRootView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var state: WindowState
    @ObservedObject private var settings = Settings.shared

    private var g: NotchGeometry { state.geometry }
    private var open: Bool { state.isOpen }
    /// Göz atmada yalnızca öne çıkan etkinlik; kullanıcı açtıysa hepsi.
    private var cards: [HubModel.Entry] {
        if state.peeking && !state.expanded { return model.primary.map { [$0] } ?? [] }
        return Array(model.ordered.prefix(g.maxCards))
    }

    private var size: CGSize {
        open ? g.openSize(cards: cards.count) : g.closedSize(hasContent: model.primary != nil)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .overlay(alignment: .top) { content.frame(width: size.width, height: size.height) }
                .clipShape(clip)
                .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 14, y: 6)
                .onTapGesture { if !open { state.onTapClosed?() } }

            if !open, let s = model.secondary {
                bubble(s)
                    .offset(x: size.width / 2 + g.bubbleGap + g.bubbleSize / 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, g.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchWindowController.spring, value: open)
        .animation(NotchWindowController.spring, value: model.entries.map(\.id))
        .animation(NotchWindowController.spring, value: model.pulsing)
    }

    // MARK: - Şekil

    private var shape: some View {
        Group {
            switch g.style {
            case .notch:
                NotchShape(ear: open ? 12 : 6, bottom: open ? 26 : 10)
                    .fill(.black)
                    .frame(width: size.width + 2 * (open ? 12 : 6), height: size.height)
            case .island:
                RoundedRectangle(cornerRadius: open ? 28 : size.height / 2, style: .continuous)
                    .fill(.black)
                    .frame(width: size.width, height: size.height)
                    .opacity(size == .zero ? 0 : 1)
            }
        }
    }

    private var clip: AnyShape {
        switch g.style {
        case .notch: AnyShape(NotchShape(ear: open ? 12 : 6, bottom: open ? 26 : 10))
        case .island: AnyShape(RoundedRectangle(cornerRadius: open ? 28 : max(size.height / 2, 1), style: .continuous))
        }
    }

    // MARK: - İçerik

    @ViewBuilder private var content: some View {
        if open {
            VStack(spacing: 0) {
                Color.clear.frame(height: g.style == .notch ? g.notchHeight : 8)
                if cards.isEmpty {
                    Text("Çentikte gösterilecek bir şey yok")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxHeight: .infinity)
                } else {
                    HStack(spacing: NotchGeometry.cardSpacing) {
                        ForEach(cards) { e in
                            CardView(entry: e, model: model, width: g.cardWidth)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .transition(.opacity)
        } else if let p = model.primary {
            HStack(spacing: 0) {
                GlyphView(glyph: p.activity.leading, side: g.notchHeight - 10)
                    .frame(width: g.wing)
                if g.style == .island {
                    Text(p.activity.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(width: g.islandMiddle)
                } else {
                    Spacer(minLength: g.notchWidth)
                }
                GlyphView(glyph: p.activity.trailing, side: g.notchHeight - 10)
                    .frame(width: g.wing)
            }
            .transition(.opacity)
        }
    }

    private func bubble(_ e: HubModel.Entry) -> some View {
        ZStack {
            Circle().fill(.black)
            GlyphView(glyph: e.activity.leading ?? e.activity.trailing, side: g.bubbleSize - 10)
        }
        .frame(width: g.bubbleSize, height: g.bubbleSize)
        .help("\(e.client.name): \(e.activity.title)")
        .onTapGesture { state.onTapClosed?() }
    }
}

/// Çentik biçimi: üst köşelerde ekrana kaynaşan içbükey "kulaklar", altta yuvarlak köşeler.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottom) }
        set { ear = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let e = min(ear, r.width / 4), b = min(bottom, r.height / 2, (r.width - 2 * e) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + e, y: r.minY + e), control: CGPoint(x: r.minX + e, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + e + b, y: r.maxY), control: CGPoint(x: r.minX + e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - b), control: CGPoint(x: r.maxX - e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - e, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Kart

struct CardView: View {
    let entry: HubModel.Entry
    @ObservedObject var model: HubModel
    let width: CGFloat

    private var a: NotchActivity { entry.activity }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let img = a.image {
                    NotchImageView(source: img)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.client.name.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(a.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if let s = a.subtitle {
                        Text(s).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { if let t = a.tapAction { model.send(entry, action: t) } }

            if let p = a.progress { ProgressRow(progress: p) { v in
                if let s = p.seekAction { model.send(entry, action: s, value: v) }
            } }

            if !a.buttons.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(a.buttons.enumerated()), id: \.offset) { _, b in
                        Button { model.send(entry, action: b.action) } label: {
                            Image(systemName: b.symbol)
                                .font(.system(size: b.prominent ? 20 : 15, weight: .semibold))
                                .foregroundStyle(Color(nsColor: b.tint?.color ?? .white))
                                .frame(maxWidth: .infinity, minHeight: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: width, height: NotchGeometry.cardHeight)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct ProgressRow: View {
    let progress: NotchProgress
    let seek: (Double) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let now = progress.elapsed(at: ctx.date)
            HStack(spacing: 8) {
                Text(progress.startLabel ?? Self.time(now))
                    .fixedSize()
                    .frame(minWidth: 34, alignment: .leading)
                GeometryReader { geo in
                    let frac = progress.total > 0 ? now / progress.total : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(Color(nsColor: progress.tint?.color ?? .white))
                            .frame(width: max(0, min(1, frac)) * geo.size.width)
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { p in
                        guard progress.seekAction != nil else { return }
                        seek(Double(p.x / geo.size.width) * progress.total)
                    }
                }
                Text(progress.endLabel ?? Self.time(progress.total))
                    .fixedSize()
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
            .frame(height: 14)
        }
    }

    static func time(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Kanat öğeleri ve görseller

struct GlyphView: View {
    let glyph: NotchGlyph?
    let side: CGFloat

    var body: some View {
        switch glyph {
        case .none:
            Color.clear.frame(width: side, height: side)
        case .image(let src):
            NotchImageView(source: src)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
        case .symbol(let name, let tint):
            // Renk SwiftUI'da foregroundStyle ile kanatlarda uygulanmıyordu; rengi simgeye gömüyoruz.
            if let img = Self.symbol(name, size: side * 0.62, color: tint?.color ?? .white) {
                Image(nsImage: img)
            }
        case .text(let s, let tint):
            Text(s)
                .font(.system(size: side * 0.55, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(nsColor: tint?.color ?? .white))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .bars(let animated, let tint):
            BarsView(animated: animated, color: Color(nsColor: tint?.color ?? .white))
                .frame(width: side * 0.8, height: side * 0.6)
        }
    }
}

extension GlyphView {
    static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
}

/// Ses dalgası çubukları.
struct BarsView: View {
    let animated: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: geo.size.width * 0.12) {
                    ForEach(0..<4, id: \.self) { i in
                        let phase = t * (5 + Double(i) * 1.7) + Double(i) * 1.3
                        let level = animated ? 0.3 + 0.7 * abs(sin(phase)) : 0.3
                        Capsule().fill(color).frame(height: geo.size.height * level)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct NotchImageView: View {
    let source: NotchImage
    @ObservedObject private var store = ImageStore.shared

    var body: some View {
        switch source {
        case .symbol(let name):
            ZStack {
                Color.white.opacity(0.1)
                Image(systemName: name).font(.system(size: 18)).foregroundStyle(.white.opacity(0.8))
            }
        default:
            if let img = store.image(for: source) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.1)
            }
        }
    }
}

/// Uzak ve gömülü görseller için küçük önbellek.
@MainActor
final class ImageStore: ObservableObject {
    static let shared = ImageStore()
    @Published private var images: [String: NSImage] = [:]
    private var loading: Set<String> = []
    private var order: [String] = []

    func image(for source: NotchImage) -> NSImage? {
        switch source {
        case .symbol: return nil
        case .data(let d):
            let key = "data:\(d.hashValue)"
            if let i = images[key] { return i }
            guard let i = NSImage(data: d) else { return nil }
            DispatchQueue.main.async { self.store(key, i) }
            return i
        case .url(let s):
            if let i = images[s] { return i }
            guard !loading.contains(s), let u = URL(string: s) else { return nil }
            loading.insert(s)
            Task {
                defer { loading.remove(s) }
                guard let (data, _) = try? await URLSession.shared.data(from: u), let i = NSImage(data: data) else { return }
                store(s, i)
            }
            return nil
        }
    }

    private func store(_ key: String, _ image: NSImage) {
        images[key] = image
        order.append(key)
        if order.count > 40 { images[order.removeFirst()] = nil }
    }
}
