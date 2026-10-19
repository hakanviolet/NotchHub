import AppKit
import Combine
import NotchKit

/// Bağlı tüm istemcilerin etkinlikleri ve aralarındaki sıralama. Çakışma kuralları burada:
/// kapalı çentikte yalnızca `primary` kanatlarda, `secondary` yandaki baloncukta görünür;
/// açılınca hepsi yan yana kart olur.
@MainActor
final class HubModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        var client: NotchClientInfo
        var activity: NotchActivity
        var updatedAt: Date
        var id: String { "\(client.id)/\(activity.id)" }
    }

    @Published private(set) var entries: [Entry] = []
    /// Şu an bağlı istemciler (etkinliği olmasa da).
    @Published private(set) var clients: [NotchClientInfo] = []
    /// Öne çıkarılmış etkinlik (pulse) ve bitiş zamanı.
    @Published private(set) var pulsing: String?
    private var pulseTask: Task<Void, Never>?

    /// Olayı ilgili istemciye iletir (HubServer bağlar).
    var deliver: ((_ clientID: String, NotchEvent) -> Void)?

    /// Gizlenmiş istemciler hariç; öncelik (+ kullanıcının eklediği), sonra en son güncellenen.
    var ordered: [Entry] {
        let s = Settings.shared
        return entries.filter { !s.isHidden($0.client.id) }.sorted { a, b in
            let pa = a.activity.priority + s.boost(a.client.id), pb = b.activity.priority + s.boost(b.client.id)
            return pa != pb ? pa > pb : a.updatedAt > b.updatedAt
        }
    }

    var primary: Entry? {
        let visible = ordered
        if let p = pulsing, let e = visible.first(where: { $0.id == p }) { return e }
        return visible.first
    }

    var secondary: Entry? {
        guard Settings.shared.showBubble else { return nil }
        let p = primary?.id
        return ordered.first { $0.id != p }
    }

    func connected(_ info: NotchClientInfo) {
        clients.removeAll { $0.id == info.id }
        clients.append(info)
        Settings.shared.remember(info)
    }

    func disconnected(_ id: String) {
        clients.removeAll { $0.id == id }
    }

    func upsert(_ a: NotchActivity, from client: NotchClientInfo) {
        let key = "\(client.id)/\(a.id)"
        if let i = entries.firstIndex(where: { $0.id == key }) {
            // Yalnızca ilerleme değiştiyse sıralamayı bozma.
            let onlyProgress = entries[i].activity.title == a.title && entries[i].activity.subtitle == a.subtitle
            entries[i].activity = a
            entries[i].client = client
            if !onlyProgress { entries[i].updatedAt = Date() }
        } else {
            entries.append(Entry(client: client, activity: a, updatedAt: Date()))
        }
    }

    func end(_ id: String, from clientID: String) {
        entries.removeAll { $0.id == "\(clientID)/\(id)" }
    }

    func removeAll(from clientID: String) {
        entries.removeAll { $0.client.id == clientID }
    }

    func pulse(_ id: String, from clientID: String, seconds: Double? = nil) {
        let seconds = seconds ?? Settings.shared.pulseSeconds
        let key = "\(clientID)/\(id)"
        guard entries.contains(where: { $0.id == key }) else { return }
        pulsing = key
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.pulsing = nil
        }
    }

    func send(_ entry: Entry, action: String, value: Double? = nil) {
        deliver?(entry.client.id, NotchEvent(activity: entry.activity.id, action: action, value: value))
    }
}
