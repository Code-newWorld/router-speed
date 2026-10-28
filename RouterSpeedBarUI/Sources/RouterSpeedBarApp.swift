import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct RouterSpeedBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = SpeedMonitor()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("上传  \(monitor.upRate)    累计  \(monitor.upTotal)")
                Text("下载  \(monitor.downRate)    累计  \(monitor.downTotal)")
                Divider()
                Text(monitor.status)
                    .foregroundStyle(.secondary)
                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
            .padding(10)
            .frame(minWidth: 260, alignment: .leading)
        } label: {
            // MenuBarExtra 的 label 用 VStack 经常不刷新、不成两行。
            // 和 AppKit 版一样画成图；.id 迫使数字变化时重绘。
            Image(nsImage: BarImage.make(up: monitor.upCompact, down: monitor.downCompact))
                .id(monitor.upCompact + monitor.downCompact)
        }
        .menuBarExtraStyle(.menu)
    }
}
