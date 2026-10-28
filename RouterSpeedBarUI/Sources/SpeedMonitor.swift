import Foundation

@MainActor
final class SpeedMonitor: ObservableObject {
    @Published var upCompact = "…"
    @Published var downCompact = "…"
    @Published var upRate = "—"
    @Published var downRate = "—"
    @Published var upTotal = "—"
    @Published var downTotal = "—"
    @Published var status = "来源：UPnP IGD  192.168.0.1"

    private var prev: UPnPClient.Totals?
    private var prevAt = Date()
    private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    deinit {
        task?.cancel()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                let totals = try UPnPClient.fetchTotals()
                apply(totals: totals, at: Date())
            } catch {
                upCompact = "—"
                downCompact = "—"
                status = "读取失败：\(error.localizedDescription)"
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
            upCompact = "…"
            downCompact = "…"
            upTotal = ByteFormat.total(totals.sent)
            downTotal = ByteFormat.total(totals.received)
            status = "来源：UPnP IGD  正在采样…"
            return
        }

        let dt = now.timeIntervalSince(prevAt)
        guard dt > 0 else { return }
        let up = Double(ByteFormat.delta(prev: prev.sent, cur: totals.sent)) / dt
        let down = Double(ByteFormat.delta(prev: prev.received, cur: totals.received)) / dt

        upCompact = ByteFormat.compactRate(up)
        downCompact = ByteFormat.compactRate(down)
        upRate = ByteFormat.rate(up)
        downRate = ByteFormat.rate(down)
        upTotal = ByteFormat.total(totals.sent)
        downTotal = ByteFormat.total(totals.received)
        status = "来源：UPnP IGD  \(String(format: "%.2fs", dt))"
    }
}
