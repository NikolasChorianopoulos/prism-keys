import AppKit

/// Menu bar icon: a keycap with a small prism, drawn as a template image.
enum MenuBarIcon {
    static func image(active: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            let cap = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 17, height: 13), xRadius: 3.5, yRadius: 3.5)
            cap.lineWidth = 1.5
            NSColor.black.setStroke()
            cap.stroke()
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: 10, y: 11.2))
            tri.line(to: NSPoint(x: 14, y: 4.5))
            tri.line(to: NSPoint(x: 6, y: 4.5))
            tri.close()
            NSColor.black.setFill()
            if active { tri.fill() } else { tri.lineWidth = 1.2; tri.stroke() }
            return true
        }
        img.isTemplate = true
        return img
    }
}

enum AppIconImage {
    static var small: NSImage {
        NSApp.applicationIconImage ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
    }
}
