import AppKit
import Combine
import NotchKit
import ServiceManagement

enum OpenMode: String, CaseIterable {
    case hover, click
}

enum CardWidth: String, CaseIterable {
    case narrow, regular, wide

    var points: CGFloat {
        switch self {
        case .narrow: 260
        case .regular: 300
        case .wide: 340
        }
    }
}

/// Bir istemci için kullanıcının seçimleri. İstemci bağlı olmasa da hatırlanır.
struct ClientPrefs: Codable, Equatable {
    var name: String
    var hidden = false
    /// Etkinliklerin önceliğine eklenir (-3...+3).
    var boost = 0
}

/// Kullanıcı ayarları; her değişiklik UserDefaults'a yazılır. Görünümler ve pencereler buna abone olur.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    /// Ayrı soketteki hub (demo kaydı, test) kullanıcının ayarlarını okumaz ve değiştirmez.
    private let d = ProcessInfo.processInfo.environment["NOTCH_SOCKET"].map { _ in
        UserDefaults(suiteName: "local.mainai.notchhub.isolated")!
    } ?? .standard

    // MARK: Görünüm

    /// Açıkken en çok kaç kart (ekrana sığmıyorsa NotchGeometry azaltır).
    @Published var maxCards: Int { didSet { d.set(maxCards, forKey: "maxCards") } }
    @Published var cardWidth: CardWidth { didSet { d.set(cardWidth.rawValue, forKey: "cardWidth") } }
    /// Kapalıyken ikinci etkinliği yandaki baloncukta göster.
    @Published var showBubble: Bool { didSet { d.set(showBubble, forKey: "showBubble") } }
    /// Çentiği her yönden ne kadar taşıracağımız (pt). Sistemin bildirdiği ölçü fiziksel çentikten bir tık küçük.
    @Published var notchOverlap: Double { didSet { d.set(notchOverlap, forKey: "notchOverlap") } }
    /// Çentiksiz ekranlarda (harici monitör...) menü çubuğunda ada göster.
    @Published var showIsland: Bool { didSet { d.set(showIsland, forKey: "showIsland") } }

    // MARK: Davranış

    @Published var openMode: OpenMode { didSet { d.set(openMode.rawValue, forKey: "openMode") } }
    /// Üzerine gelince açılmadan önce bekleme (sn).
    @Published var hoverDelay: Double { didSet { d.set(hoverDelay, forKey: "hoverDelay") } }
    /// Öne çıkarılan (pulse) etkinliğin açık kalma süresi (sn).
    @Published var pulseSeconds: Double { didSet { d.set(pulseSeconds, forKey: "pulseSeconds") } }

    // MARK: Uygulamalar

    @Published private(set) var clients: [String: ClientPrefs] {
        didSet { d.set(try? JSONEncoder().encode(clients), forKey: "clients") }
    }

    private init() {
        d.register(defaults: [
            "maxCards": 3, "cardWidth": CardWidth.regular.rawValue, "showBubble": true, "notchOverlap": 2.0,
            "showIsland": true, "openMode": OpenMode.hover.rawValue, "hoverDelay": 0.12, "pulseSeconds": 3.0,
        ])
        maxCards = d.integer(forKey: "maxCards")
        cardWidth = CardWidth(rawValue: d.string(forKey: "cardWidth") ?? "") ?? .regular
        showBubble = d.bool(forKey: "showBubble")
        notchOverlap = d.double(forKey: "notchOverlap")
        showIsland = d.bool(forKey: "showIsland")
        openMode = OpenMode(rawValue: d.string(forKey: "openMode") ?? "") ?? .hover
        hoverDelay = d.double(forKey: "hoverDelay")
        pulseSeconds = d.double(forKey: "pulseSeconds")
        clients = d.data(forKey: "clients").flatMap { try? JSONDecoder().decode([String: ClientPrefs].self, from: $0) } ?? [:]
    }

    func resetAppearance() {
        maxCards = 3
        cardWidth = .regular
        showBubble = true
        notchOverlap = 2
        showIsland = true
    }

    // MARK: İstemciler

    /// İstemci bağlandığında adını hatırla (ayarlarda bağlı değilken de listelensin).
    func remember(_ info: NotchClientInfo) {
        if clients[info.id]?.name != info.name {
            clients[info.id, default: ClientPrefs(name: info.name)].name = info.name
        }
    }

    func prefs(_ id: String) -> ClientPrefs? { clients[id] }

    func setHidden(_ id: String, _ hidden: Bool) { clients[id]?.hidden = hidden }

    func setBoost(_ id: String, _ boost: Int) { clients[id]?.boost = min(3, max(-3, boost)) }

    func forget(_ id: String) { clients[id] = nil }

    func isHidden(_ id: String) -> Bool { clients[id]?.hidden ?? false }

    func boost(_ id: String) -> Int { clients[id]?.boost ?? 0 }

    // MARK: Oturum açılışı

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Oturum açılışı ayarı değiştirilemedi"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
