import Foundation
import Network

/// NotchHub'a bağlanan istemci. NotchHub çalışmıyorsa sessizce bekler ve açıldığında bağlanır;
/// bağlanınca son durumdaki tüm etkinlikleri yeniden gönderir. Tüm geri çağrılar ana kuyrukta gelir.
///
/// ```swift
/// let notch = NotchClient(id: "com.ornek.zamanlayici", name: "Zamanlayıcı")
/// notch.onEvent = { event in if event.action == "stop" { ... } }
/// notch.update(NotchActivity(id: "timer", leading: .symbol("timer"), trailing: .text("04:59"), title: "Çay"))
/// ```
public final class NotchClient: @unchecked Sendable {
    public var onEvent: ((NotchEvent) -> Void)?
    /// Bağlantı durumu değiştiğinde (true = NotchHub'a bağlı).
    public var onConnectionChange: ((Bool) -> Void)?

    private let info: NotchClientInfo
    private let queue = DispatchQueue(label: "NotchKit.client")
    private var connection: NWConnection?
    private var framing = NotchFraming()
    private var activities: [String: NotchActivity] = [:]   // queue üzerinde
    private var connected = false
    private var stopped = false

    public init(id: String, name: String) {
        info = NotchClientInfo(id: id, name: name)
        queue.async { self.connect() }
    }

    deinit { connection?.cancel() }

    /// Etkinliği ekler ya da günceller. Aynı içerik tekrar gönderilmez.
    public func update(_ activity: NotchActivity) {
        queue.async {
            guard self.activities[activity.id] != activity else { return }
            self.activities[activity.id] = activity
            self.send(.activity(activity: activity))
        }
    }

    public func end(_ id: String) {
        queue.async {
            guard self.activities.removeValue(forKey: id) != nil else { return }
            self.send(.end(id: id))
        }
    }

    /// Etkinliği birkaç saniyeliğine öne çıkarır (ör. yeni şarkı başladı).
    public func pulse(_ id: String) {
        queue.async { self.send(.pulse(id: id)) }
    }

    public func stop() {
        queue.async {
            self.stopped = true
            self.connection?.cancel()
        }
    }

    // MARK: - Bağlantı

    private func connect() {
        guard !stopped else { return }
        let conn = NWConnection(to: .unix(path: NotchProtocol.socketPath), using: .tcp)
        connection = conn
        framing = NotchFraming()
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                connected = true
                notifyConnection(true)
                send(.hello(client: info))
                for a in activities.values { send(.activity(activity: a)) }
                receive(on: conn)
            case .failed, .cancelled, .waiting:
                guard conn === connection else { return }
                if connected { notifyConnection(false) }
                connected = false
                conn.cancel()
                connection = nil
                // NotchHub kapalı ya da yeniden başlıyor: biraz sonra tekrar dene.
                queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connect() }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self, conn === connection else { return }
            if let data, !data.isEmpty {
                for case .event(let e) in framing.feed(data) {
                    DispatchQueue.main.async { self.onEvent?(e) }
                }
            }
            if done || error != nil {
                conn.cancel()   // stateUpdateHandler yeniden bağlanmayı ayarlar
            } else {
                receive(on: conn)
            }
        }
    }

    private func send(_ m: NotchMessage) {
        guard connected, let conn = connection, let data = NotchFraming.encode(m) else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    private func notifyConnection(_ up: Bool) {
        DispatchQueue.main.async { self.onConnectionChange?(up) }
    }
}
