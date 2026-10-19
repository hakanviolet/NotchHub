import Foundation

// NotchHub protokolü
//
// İstemciler NotchHub'a `NotchProtocol.socketPath` adresindeki Unix soketi üzerinden bağlanır ve satır başına
// bir JSON mesajı gönderir. İstemci çizim yapmaz; ne gösterileceğini `NotchActivity` ile tarif eder, NotchHub çizer.
// Böylece birden çok uygulama çentiği aynı anda kullanabilir ve hiçbiri diğerinin üstüne binmez.
//
//   istemci → hub   {"type":"hello","version":1,"client":{"id":"com.ornek.app","name":"Örnek"}}
//                   {"type":"activity","activity":{...}}      ekle ya da güncelle
//                   {"type":"end","id":"etkinlik-kimliği"}    kaldır
//                   {"type":"pulse","id":"etkinlik-kimliği"}  birkaç saniyeliğine öne çıkar
//   hub → istemci   {"type":"welcome","version":1}                   hello'ya yanıt
//                   {"type":"event","event":{"activity":"...","action":"toggle","value":12.5}}
//                   {"type":"error","code":"unsupported-version","message":"..."}   ardından bağlantı kapanır
//
// Sürümleme: `hello` içindeki `version` istemcinin hangi protokol sürümüne göre yazıldığını söyler; yoksa 1 sayılır.
// Yeni alanlar ve mesaj türleri sürümü artırmadan, isteğe bağlı olarak eklenir: iki taraf da bilmediği alanları
// ve türleri yok sayar. Sürüm yalnızca eski istemcileri bozacak bir değişiklikte artar; hub
// `minimumVersion`'dan eski istemcileri `unsupported-version` hatasıyla reddeder.

public enum NotchProtocol {
    /// Bu kütüphanenin ve hub'ın konuştuğu sürüm.
    public static let version = 1
    /// Hub'ın hâlâ kabul ettiği en eski istemci sürümü.
    public static let minimumVersion = 1

    /// `NOTCH_SOCKET` ortam değişkeni varsayılanı değiştirir (demo kaydı, test): o yolda ayrı bir hub çalışır,
    /// varsayılan soketteki istemciler etkilenmez.
    public static var socketPath: String {
        if let p = ProcessInfo.processInfo.environment["NOTCH_SOCKET"], !p.isEmpty { return p }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchHub", isDirectory: true)
        return dir.appendingPathComponent("hub.sock").path
    }
}

/// Çentikte görünen tek bir canlı etkinlik (çalan şarkı, zamanlayıcı, indirme...).
public struct NotchActivity: Codable, Equatable, Sendable {
    /// İstemci içinde benzersiz kimlik.
    public var id: String
    /// Büyük olan kapalı çentikte önce gösterilir. Eşitse en son güncellenen kazanır.
    public var priority: Int
    /// Kapalı çentiğin sol ve sağ kanadı.
    public var leading: NotchGlyph?
    public var trailing: NotchGlyph?
    /// Açılınca görünen kart.
    public var image: NotchImage?
    public var title: String
    public var subtitle: String?
    public var buttons: [NotchButton]
    public var progress: NotchProgress?
    /// Karta tıklanınca gönderilecek eylem (ör. uygulamayı öne getirmek).
    public var tapAction: String?

    public init(id: String, priority: Int = 0, leading: NotchGlyph? = nil, trailing: NotchGlyph? = nil,
                image: NotchImage? = nil, title: String, subtitle: String? = nil, buttons: [NotchButton] = [],
                progress: NotchProgress? = nil, tapAction: String? = nil) {
        self.id = id
        self.priority = priority
        self.leading = leading
        self.trailing = trailing
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.buttons = buttons
        self.progress = progress
        self.tapAction = tapAction
    }

    // Elle yazılan (ör. Python) istemciler için: yalnızca `id` ve `title` zorunlu.
    private enum CodingKeys: String, CodingKey {
        case id, priority, leading, trailing, image, title, subtitle, buttons, progress, tapAction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        leading = try c.decodeIfPresent(NotchGlyph.self, forKey: .leading)
        trailing = try c.decodeIfPresent(NotchGlyph.self, forKey: .trailing)
        image = try c.decodeIfPresent(NotchImage.self, forKey: .image)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        buttons = try c.decodeIfPresent([NotchButton].self, forKey: .buttons) ?? []
        progress = try c.decodeIfPresent(NotchProgress.self, forKey: .progress)
        tapAction = try c.decodeIfPresent(String.self, forKey: .tapAction)
    }
}

/// Görsel kaynağı: uzak adres, gömülü veri (base64 PNG/JPEG) ya da SF Symbol.
public enum NotchImage: Codable, Equatable, Sendable {
    case url(String)
    case data(Data)
    case symbol(String)
}

/// Kapalı çentiğin kanatlarına sığan küçük öğe.
public enum NotchGlyph: Codable, Equatable, Sendable {
    case image(NotchImage)
    case symbol(String, tint: NotchTint? = nil)
    case text(String, tint: NotchTint? = nil)
    /// Ses dalgası çubukları; `animated` iken oynar.
    case bars(animated: Bool, tint: NotchTint? = nil)
}

public enum NotchTint: String, Codable, Sendable {
    case white, red, orange, yellow, green, blue, purple, pink, gray
}

public struct NotchButton: Codable, Equatable, Sendable {
    public var action: String
    public var symbol: String
    public var tint: NotchTint?
    /// Vurgulu (ör. ana oynat/duraklat düğmesi biraz daha büyük çizilir).
    public var prominent: Bool

    public init(action: String, symbol: String, tint: NotchTint? = nil, prominent: Bool = false) {
        self.action = action
        self.symbol = symbol
        self.tint = tint
        self.prominent = prominent
    }

    private enum CodingKeys: String, CodingKey { case action, symbol, tint, prominent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(String.self, forKey: .action)
        symbol = try c.decode(String.self, forKey: .symbol)
        tint = try c.decodeIfPresent(NotchTint.self, forKey: .tint)
        prominent = try c.decodeIfPresent(Bool.self, forKey: .prominent) ?? false
    }
}

/// İlerleme: `elapsed` saniye, `at` anında ölçüldü ve `rate` hızla ilerliyor. Hub aradaki süreyi kendisi hesaplar,
/// istemcinin her saniye güncelleme göndermesi gerekmez.
public struct NotchProgress: Codable, Equatable, Sendable {
    public var elapsed: Double
    public var total: Double
    public var rate: Double
    public var at: Date
    /// Tanımlıysa çubuğa tıklamak bu eylemi saniye cinsinden `value` ile gönderir.
    public var seekAction: String?
    /// Çubuğun iki yanındaki yazılar; verilmezse geçen/toplam süre (`1:05` / `3:33`) yazılır.
    public var startLabel: String?
    public var endLabel: String?
    /// Dolu kısmın rengi (varsayılan beyaz). Ör. bütçe aşılınca kırmızı.
    public var tint: NotchTint?

    public init(elapsed: Double, total: Double, rate: Double, at: Date = Date(), seekAction: String? = nil,
                startLabel: String? = nil, endLabel: String? = nil, tint: NotchTint? = nil) {
        self.elapsed = elapsed
        self.total = total
        self.rate = rate
        self.at = at
        self.seekAction = seekAction
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.tint = tint
    }

    private enum CodingKeys: String, CodingKey { case elapsed, total, rate, at, seekAction, startLabel, endLabel, tint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elapsed = try c.decode(Double.self, forKey: .elapsed)
        total = try c.decode(Double.self, forKey: .total)
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? 0
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? Date()
        seekAction = try c.decodeIfPresent(String.self, forKey: .seekAction)
        startLabel = try c.decodeIfPresent(String.self, forKey: .startLabel)
        endLabel = try c.decodeIfPresent(String.self, forKey: .endLabel)
        tint = try c.decodeIfPresent(NotchTint.self, forKey: .tint)
    }

    public func elapsed(at date: Date) -> Double {
        min(max(elapsed + date.timeIntervalSince(at) * rate, 0), total)
    }
}

public struct NotchClientInfo: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Hub'dan istemciye: kullanıcı bir düğmeye, karta ya da ilerleme çubuğuna dokundu.
public struct NotchEvent: Codable, Equatable, Sendable {
    public var activity: String
    public var action: String
    public var value: Double?

    public init(activity: String, action: String, value: Double? = nil) {
        self.activity = activity
        self.action = action
        self.value = value
    }
}

/// Kablodaki mesaj.
public enum NotchMessage: Codable, Equatable, Sendable {
    case hello(client: NotchClientInfo, version: Int = NotchProtocol.version)
    case welcome(version: Int)
    case activity(activity: NotchActivity)
    case end(id: String)
    case pulse(id: String)
    case event(event: NotchEvent)
    case error(code: String, message: String)

    private enum CodingKeys: String, CodingKey { case type, version, client, activity, id, event, code, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hello":
            // `version` sonradan eklendi; göndermeyen istemciler v1'dir.
            self = .hello(client: try c.decode(NotchClientInfo.self, forKey: .client),
                          version: try c.decodeIfPresent(Int.self, forKey: .version) ?? 1)
        case "welcome": self = .welcome(version: try c.decodeIfPresent(Int.self, forKey: .version) ?? 1)
        case "activity": self = .activity(activity: try c.decode(NotchActivity.self, forKey: .activity))
        case "end": self = .end(id: try c.decode(String.self, forKey: .id))
        case "pulse": self = .pulse(id: try c.decode(String.self, forKey: .id))
        case "event": self = .event(event: try c.decode(NotchEvent.self, forKey: .event))
        case "error":
            self = .error(code: try c.decode(String.self, forKey: .code),
                          message: try c.decodeIfPresent(String.self, forKey: .message) ?? "")
        case let t: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "bilinmeyen tür \(t)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let client, let version):
            try c.encode("hello", forKey: .type); try c.encode(version, forKey: .version)
            try c.encode(client, forKey: .client)
        case .welcome(let version): try c.encode("welcome", forKey: .type); try c.encode(version, forKey: .version)
        case .activity(let a): try c.encode("activity", forKey: .type); try c.encode(a, forKey: .activity)
        case .end(let id): try c.encode("end", forKey: .type); try c.encode(id, forKey: .id)
        case .pulse(let id): try c.encode("pulse", forKey: .type); try c.encode(id, forKey: .id)
        case .event(let e): try c.encode("event", forKey: .type); try c.encode(e, forKey: .event)
        case .error(let code, let message):
            try c.encode("error", forKey: .type); try c.encode(code, forKey: .code); try c.encode(message, forKey: .message)
        }
    }
}

/// Satır sonuyla ayrılmış JSON çerçeveleme.
public struct NotchFraming {
    private var buffer = Data()
    public init() {}

    public static func encode(_ m: NotchMessage) -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard var d = try? enc.encode(m) else { return nil }
        d.append(0x0A)
        return d
    }

    /// Gelen baytları ekler, tamamlanan mesajları döndürür. Bozuk satırlar atlanır.
    public mutating func feed(_ data: Data) -> [NotchMessage] {
        buffer.append(data)
        var out: [NotchMessage] = []
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let m = try? dec.decode(NotchMessage.self, from: line) { out.append(m) }
        }
        // Kötü niyetli ya da bozuk istemci belleği şişirmesin.
        if buffer.count > 4_000_000 { buffer.removeAll() }
        return out
    }
}
