import AppKit

enum BarImage {
    static let size = NSSize(width: 54, height: 20)

    static func make(up: String, down: String) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            (up as NSString).draw(at: NSPoint(x: 1, y: 0.5), withAttributes: attrs)
            (down as NSString).draw(at: NSPoint(x: 1, y: 10.5), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var upItem: NSMenuItem!
    private var downItem: NSMenuItem!
    private var statusLine: NSMenuItem!
    private var prev: UPnPClient.Totals?
    private var prevAt = Date()
    private var pollTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: BarImage.size.width)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = BarImage.make(up: "  …", down: "  …")

        let menu = NSMenu()
        upItem = NSMenuItem(title: "上传  —", action: nil, keyEquivalent: "")
        downItem = NSMenuItem(title: "下载  —", action: nil, keyEquivalent: "")
        statusLine = NSMenuItem(title: "来源：UPnP IGD  192.168.0.1", action: nil, keyEquivalent: "")
        upItem.isEnabled = false
        downItem.isEnabled = false
        statusLine.isEnabled = false
        menu.addItem(upItem)
        menu.addItem(downItem)
        menu.addItem(.separator())
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setBar(up: String, down: String) {
        statusItem.button?.image = BarImage.make(up: up, down: down)
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                let totals = try UPnPClient.fetchTotals()
                let now = Date()
                await MainActor.run {
                    self.apply(totals: totals, at: now)
                }
            } catch {
                await MainActor.run {
                    self.setBar(up: "  —", down: "  —")
                    self.statusLine.title = "读取失败：\(error.localizedDescription)"
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func apply(totals: UPnPClient.Totals, at now: Date) {
        defer {
            prev = totals
            prevAt = now
        }
        guard let prev else {
            setBar(up: "  …", down: "  …")
            upItem.title = "上传  累计  \(ByteFormat.total(totals.sent))"
            downItem.title = "下载  累计  \(ByteFormat.total(totals.received))"
            statusLine.title = "来源：UPnP IGD  正在采样…"
            return
        }

        let dt = now.timeIntervalSince(prevAt)
        guard dt > 0 else { return }
        let up = Double(ByteFormat.delta(prev: prev.sent, cur: totals.sent)) / dt
        let down = Double(ByteFormat.delta(prev: prev.received, cur: totals.received)) / dt

        setBar(up: ByteFormat.compactRate(up), down: ByteFormat.compactRate(down))
        upItem.title = "上传  \(ByteFormat.rate(up))    累计  \(ByteFormat.total(totals.sent))"
        downItem.title = "下载  \(ByteFormat.rate(down))    累计  \(ByteFormat.total(totals.received))"
        statusLine.title = "来源：UPnP IGD  \(String(format: "%.2fs", dt))"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
