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
