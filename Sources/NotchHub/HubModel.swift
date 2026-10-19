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
    /// Öne çıkarılmış etkinlik (pulse) ve bitiş zamanı.
    @Published private(set) var pulsing: String?
    private var pulseTask: Task<Void, Never>?

    /// Olayı ilgili istemciye iletir (HubServer bağlar).
    var deliver: ((_ clientID: String, NotchEvent) -> Void)?

    /// Öncelik, sonra en son güncellenen.
    var ordered: [Entry] {
        entries.sorted { a, b in
            a.activity.priority != b.activity.priority
                ? a.activity.priority > b.activity.priority
                : a.updatedAt > b.updatedAt
        }
    }

    var primary: Entry? {
        if let p = pulsing, let e = entries.first(where: { $0.id == p }) { return e }
        return ordered.first
    }

    var secondary: Entry? { ordered.first { $0.id != primary?.id } }

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

    func pulse(_ id: String, from clientID: String, seconds: Double = 3) {
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
