import Foundation
import Network
import NotchKit

/// Unix soketinde istemcileri dinler; mesajları HubModel'e aktarır, olayları istemcilere geri yollar.
@MainActor
final class HubServer {
    private let model: HubModel
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private let debug = ProcessInfo.processInfo.environment["NOTCH_DEBUG"] != nil

    private final class Client {
        let connection: NWConnection
        var info: NotchClientInfo?
        var framing = NotchFraming()
        init(_ c: NWConnection) { connection = c }
    }

    init(model: HubModel) {
        self.model = model
        model.deliver = { [weak self] clientID, event in self?.deliver(event, to: clientID) }
    }

    func start() throws {
        let path = NotchProtocol.socketPath
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // Önceki çalışmadan kalan soket dosyası bağlanmayı engeller.
        unlink(path)

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: path)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state {
                MainActor.assumeIsolated { self?.log("dinleyici hatası: \(e)") }
            }
        }
        l.start(queue: .main)
        listener = l
        log("dinleniyor: \(path)")
    }

    func stop() {
        listener?.cancel()
        for c in clients.values { c.connection.cancel() }
        unlink(NotchProtocol.socketPath)
    }

    private func accept(_ conn: NWConnection) {
        let c = Client(conn)
        let key = ObjectIdentifier(c)
        clients[key] = c
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated { self?.drop(key) }
            default: break
            }
        }
        conn.start(queue: .main)
        receive(key)
    }

    private func receive(_ key: ObjectIdentifier) {
        guard let c = clients[key] else { return }
        c.connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, let c = self.clients[key] else { return }
                if let data, !data.isEmpty {
                    for m in c.framing.feed(data) { self.handle(m, from: c) }
                }
                if done || error != nil { c.connection.cancel() } else { self.receive(key) }
            }
        }
    }

    private func handle(_ m: NotchMessage, from c: Client) {
        switch m {
        case .hello(let info):
            // Aynı istemci yeniden bağlandıysa eski bağlantısını kapat.
            for (k, other) in clients where other !== c && other.info?.id == info.id {
                other.connection.cancel()
                clients[k] = nil
            }
            c.info = info
            log("bağlandı: \(info.name) (\(info.id))")
        case .activity(let a):
            guard let info = c.info else { return }
            model.upsert(a, from: info)
        case .end(let id):
            guard let info = c.info else { return }
            model.end(id, from: info.id)
        case .pulse(let id):
            guard let info = c.info else { return }
            model.pulse(id, from: info.id)
        case .event:
            break   // istemciden olay gelmez
        }
    }

    private func drop(_ key: ObjectIdentifier) {
        guard let c = clients.removeValue(forKey: key) else { return }
        if let info = c.info {
            // Aynı kimlikle yeni bir bağlantı varsa etkinliklerini silme.
            if !clients.values.contains(where: { $0.info?.id == info.id }) { model.removeAll(from: info.id) }
            log("ayrıldı: \(info.name)")
        }
    }

    private func deliver(_ e: NotchEvent, to clientID: String) {
        guard let c = clients.values.first(where: { $0.info?.id == clientID }),
              let data = NotchFraming.encode(.event(event: e)) else { return }
        c.connection.send(content: data, completion: .contentProcessed { _ in })
        log("olay → \(clientID): \(e.action)")
    }

    private func log(_ s: String) { if debug { print("[hub] \(s)") } }
}
