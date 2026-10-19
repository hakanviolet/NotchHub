import AppKit
import NotchKit
import SwiftUI

/// Ayarlar penceresi (menü çubuğu → Ayarlar…, ⌘,). Uygulama Dock'ta görünmediği için pencere tek örnek tutulur.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: HubModel
    private let nav = SettingsNav()

    init(model: HubModel) { self.model = model }

    func show(tab: SettingsTab? = nil) {
        if let tab { nav.tab = tab }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, nav: nav))
            let w = NSWindow(contentViewController: host)
            w.title = "NotchHub Ayarları"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Hata ayıklama: pencerenin içeriğini PNG olarak yazar.
    func snapshot(to path: String) {
        guard let v = window?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

enum SettingsTab: String {
    case appearance, behavior, clients, about
}

@MainActor
final class SettingsNav: ObservableObject {
    @Published var tab: SettingsTab = .appearance
}

struct SettingsView: View {
    @ObservedObject var model: HubModel
    @ObservedObject var nav: SettingsNav

    var body: some View {
        TabView(selection: $nav.tab) {
            AppearanceTab()
                .tabItem { Label("Görünüm", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)
            BehaviorTab()
                .tabItem { Label("Davranış", systemImage: "cursorarrow.motionlines") }
                .tag(SettingsTab.behavior)
            ClientsTab(model: model)
                .tabItem { Label("Uygulamalar", systemImage: "square.stack.3d.up") }
                .tag(SettingsTab.clients)
            AboutTab()
                .tabItem { Label("Hakkında", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 520, height: 500)
    }
}

// MARK: - Görünüm

private struct AppearanceTab: View {
    @ObservedObject private var s = Settings.shared

    var body: some View {
        Form {
            Section("Açık çentik") {
                Picker("En çok kart", selection: $s.maxCards) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Kart genişliği", selection: $s.cardWidth) {
                    Text("Dar").tag(CardWidth.narrow)
                    Text("Normal").tag(CardWidth.regular)
                    Text("Geniş").tag(CardWidth.wide)
                }
                .pickerStyle(.segmented)
            }
            Section("Kapalı çentik") {
                Toggle("İkinci etkinliği yandaki baloncukta göster", isOn: $s.showBubble)
                LabeledContent("Çentik taşması") {
                    HStack {
                        Slider(value: $s.notchOverlap, in: 0...4, step: 0.5)
                        Text(String(format: "%.1f pt", s.notchOverlap))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Text("Siyah şeklin kenarlarında fiziksel çentik görünüyorsa artır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Çentiksiz ekranlar") {
                Toggle("Menü çubuğunda ada göster", isOn: $s.showIsland)
                Text("Harici monitörler ve çentiği gizleyen çözünürlükler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Varsayılanlara Dön") { s.resetAppearance() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Davranış

private struct BehaviorTab: View {
    @ObservedObject private var s = Settings.shared

    var body: some View {
        Form {
            Section("Açılma") {
                Picker("Çentik açılsın", selection: $s.openMode) {
                    Text("Üzerine gelince").tag(OpenMode.hover)
                    Text("Tıklayınca").tag(OpenMode.click)
                }
                .pickerStyle(.radioGroup)
                LabeledContent("Üzerine gelme gecikmesi") {
                    HStack {
                        Slider(value: $s.hoverDelay, in: 0...0.6, step: 0.04)
                        Text(String(format: "%.2f sn", s.hoverDelay))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(s.openMode != .hover)
            }
            Section("Öne çıkarma") {
                LabeledContent("Açık kalma süresi") {
                    HStack {
                        Slider(value: $s.pulseSeconds, in: 1...8, step: 0.5)
                        Text(String(format: "%.1f sn", s.pulseSeconds))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Text("Bir uygulama \u{201C}yeni şarkı başladı\u{201D} gibi bir anı öne çıkardığında.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Başlangıç") {
                Toggle("Oturum açılışında başlat", isOn: Binding(get: { s.launchAtLogin }, set: { s.launchAtLogin = $0 }))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Uygulamalar

private struct ClientsTab: View {
    @ObservedObject var model: HubModel
    @ObservedObject private var s = Settings.shared

    private struct Row: Identifiable {
        let id: String
        let name: String
        let connected: Bool
        let activities: Int
    }

    /// Bağlı olanlar önce, sonra daha önce görülmüş olanlar.
    private var rows: [Row] {
        let live = Set(model.clients.map(\.id))
        let ids = Set(s.clients.keys).union(live)
        return ids.map { id in
            Row(id: id,
                name: model.clients.first { $0.id == id }?.name ?? s.prefs(id)?.name ?? id,
                connected: live.contains(id),
                activities: model.entries.filter { $0.client.id == id }.count)
        }
        .sorted { ($0.connected ? 0 : 1, $0.name.lowercased()) < ($1.connected ? 0 : 1, $1.name.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Form satırları Stepper/Toggle'ı ayrı etiketli kontrol sayıp dağıtıyor; bu yüzden düz liste.
            List {
                if rows.isEmpty {
                    Text("Henüz bağlanan bir uygulama yok.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { r in row(r).padding(.vertical, 4) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Öncelik, uygulamanın kendi önceliğine eklenir; büyük olan kapalı çentikte önce gösterilir. "
                 + "Gizlenen uygulama bağlı kalır ama çentikte görünmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private func row(_ r: Row) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(r.connected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .help(r.connected ? "Bağlı" : "Bağlı değil")
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name)
                Text(r.connected ? "\(r.id) · \(r.activities) etkinlik" : "\(r.id) · bağlı değil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            let boost = s.boost(r.id)
            Text(boost == 0 ? "Öncelik 0" : String(format: "Öncelik %+d", boost))
                .monospacedDigit()
                .font(.callout)
                .foregroundStyle(boost == 0 ? .secondary : .primary)
            Stepper("Öncelik", value: Binding(get: { boost }, set: { s.setBoost(r.id, $0) }), in: -3...3)
                .labelsHidden()
            Toggle("Göster", isOn: Binding(get: { !s.isHidden(r.id) }, set: { s.setHidden(r.id, !$0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Çentikte göster")
            if !r.connected {
                Button { s.forget(r.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Listeden kaldır")
            }
        }
    }
}

// MARK: - Hakkında

private struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "geliştirme"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            VStack(spacing: 4) {
                Text("NotchHub").font(.title2.weight(.semibold))
                Text("Sürüm \(version)").foregroundStyle(.secondary)
            }
            Form {
                LabeledContent("Protokol", value: "v\(NotchProtocol.version) (en az v\(NotchProtocol.minimumVersion))")
                LabeledContent("Soket") {
                    HStack(spacing: 6) {
                        Text(NotchProtocol.socketPath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NotchProtocol.socketPath)])
                        } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help("Finder'da göster")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 130)
            Link("github.com/hakanviolet/NotchHub", destination: URL(string: "https://github.com/hakanviolet/NotchHub")!)
            Text("MIT Lisansı").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
