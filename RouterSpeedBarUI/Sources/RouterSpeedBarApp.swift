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
                Text("Up    \(monitor.upRate)    Total  \(monitor.upTotal)")
                Text("Down  \(monitor.downRate)    Total  \(monitor.downTotal)")
                Divider()
                Text(monitor.status)
                    .foregroundStyle(.secondary)
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(10)
            .frame(minWidth: 260, alignment: .leading)
        } label: {
            // MenuBarExtra labels ignore VStack/two-line Text and often skip refreshes.
            // Draw the same two-line image as the AppKit app; .id forces a redraw.
            Image(nsImage: BarImage.make(up: monitor.upCompact, down: monitor.downCompact))
                .id(monitor.upCompact + monitor.downCompact)
        }
        .menuBarExtraStyle(.menu)
    }
}
