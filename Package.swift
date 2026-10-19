// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchHub",
    platforms: [.macOS(.v14)],
    products: [
        // Çentikte görünmek isteyen uygulamalar yalnızca bu kütüphaneye bağlanır.
        .library(name: "NotchKit", targets: ["NotchKit"]),
        .executable(name: "NotchHub", targets: ["NotchHub"]),
    ],
    targets: [
        .target(name: "NotchKit", path: "Sources/NotchKit"),
        .executableTarget(name: "NotchHub", dependencies: ["NotchKit"], path: "Sources/NotchHub"),
    ]
)
