// Hata ayıklama: NOTCH_DEBUG ile çalışan NotchHub'a komut gönderir. Kullanım: swift tools/notchctl.swift open|close|snapshot:/klasör
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    .init("local.mainai.notchhub.debug"), object: CommandLine.arguments.dropFirst().first ?? "open",
    userInfo: nil, deliverImmediately: true)
