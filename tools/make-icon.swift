// Antigravity'nin ürettiği opak görselden kırmızı kareyi kırpar, macOS ikon ızgarasına
// (1024 tuvalde 824'lük yuvarlatılmış kare) yerleştirir ve AppIcon.icns üretir.
// Kullanım: swift tools/make-icon.swift Resources/icon-source.png Resources/AppIcon.icns
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("kullanım: make-icon.swift <kaynak.png> <çıktı.icns>")
}

// Kırmızı bölgenin sınırlarını bul.
let w = cg.width, h = cg.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w {
    let i = (y * w + x) * 4
    let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
    if r - g > 70 && r - b > 70 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
// Parlak kenar çizgisini atmak için biraz içeriden kırp.
let inset = Double(maxX - minX) * 0.02
let crop = CGRect(x: Double(minX) + inset, y: Double(minY) + inset,
                  width: Double(maxX - minX) - 2 * inset, height: Double(maxY - minY) - 2 * inset)
// CGContext belleği alttan başlar; cropping(to:) üstten. Y'yi çevir.
let cropTop = CGRect(x: crop.minX, y: Double(h) - crop.maxY, width: crop.width, height: crop.height)
let body = cg.cropping(to: cropTop)!

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext
    c.interpolationQuality = .high
    let side = s * 824 / 1024
    let rect = CGRect(x: (s - side) / 2, y: (s - side) / 2 - s * 0.01, width: side, height: side)
    let path = CGPath(roundedRect: rect, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02,
                color: NSColor.black.withAlphaComponent(0.35).cgColor)
    c.addPath(path); c.setFillColor(NSColor.black.cgColor); c.fillPath()
    c.restoreGState()
    c.addPath(path); c.clip()
    c.draw(body, in: rect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", args[2]]
try! p.run(); p.waitUntilExit()
try! render(512).write(to: URL(fileURLWithPath: args[2]).deletingPathExtension().appendingPathExtension("png"))
print("İkon: \(args[2])")
