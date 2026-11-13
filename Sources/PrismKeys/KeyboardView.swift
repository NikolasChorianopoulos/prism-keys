import PrismCore
import SwiftUI

/// Physical layout (in key units) of the BlackWidow Chroma, for drawing.
enum VisualLayout {
    struct Cap: Identifiable { let id: String; let x: Double; let y: Double; let w: Double; let h: Double }

    static let caps: [Cap] = {
        // nil name = gap
        let rows: [[(String?, Double, Double)]] = [
            [(nil, 1.25, 1), ("esc", 1, 1), (nil, 1, 1), ("f1", 1, 1), ("f2", 1, 1), ("f3", 1, 1), ("f4", 1, 1), (nil, 0.5, 1),
             ("f5", 1, 1), ("f6", 1, 1), ("f7", 1, 1), ("f8", 1, 1), (nil, 0.5, 1), ("f9", 1, 1), ("f10", 1, 1), ("f11", 1, 1), ("f12", 1, 1),
             (nil, 0.25, 1), ("printscreen", 1, 1), ("scrolllock", 1, 1), ("pause", 1, 1)],
            [("m1", 1, 1), (nil, 0.25, 1), ("grave", 1, 1), ("1", 1, 1), ("2", 1, 1), ("3", 1, 1), ("4", 1, 1), ("5", 1, 1), ("6", 1, 1),
             ("7", 1, 1), ("8", 1, 1), ("9", 1, 1), ("0", 1, 1), ("minus", 1, 1), ("equal", 1, 1), ("backspace", 2, 1), (nil, 0.25, 1),
             ("insert", 1, 1), ("home", 1, 1), ("pageup", 1, 1), (nil, 0.25, 1), ("numlock", 1, 1), ("kp_divide", 1, 1), ("kp_multiply", 1, 1), ("kp_minus", 1, 1)],
            [("m2", 1, 1), (nil, 0.25, 1), ("tab", 1.5, 1), ("q", 1, 1), ("w", 1, 1), ("e", 1, 1), ("r", 1, 1), ("t", 1, 1), ("y", 1, 1),
             ("u", 1, 1), ("i", 1, 1), ("o", 1, 1), ("p", 1, 1), ("lbracket", 1, 1), ("rbracket", 1, 1), ("backslash", 1.5, 1), (nil, 0.25, 1),
             ("delete", 1, 1), ("end", 1, 1), ("pagedown", 1, 1), (nil, 0.25, 1), ("kp7", 1, 1), ("kp8", 1, 1), ("kp9", 1, 1), ("kp_plus", 1, 2)],
            [("m3", 1, 1), (nil, 0.25, 1), ("capslock", 1.75, 1), ("a", 1, 1), ("s", 1, 1), ("d", 1, 1), ("f", 1, 1), ("g", 1, 1), ("h", 1, 1),
             ("j", 1, 1), ("k", 1, 1), ("l", 1, 1), ("semicolon", 1, 1), ("quote", 1, 1), ("enter", 2.25, 1), (nil, 3.5, 1),
             ("kp4", 1, 1), ("kp5", 1, 1), ("kp6", 1, 1)],
            [("m4", 1, 1), (nil, 0.25, 1), ("lshift", 2.25, 1), ("z", 1, 1), ("x", 1, 1), ("c", 1, 1), ("v", 1, 1), ("b", 1, 1), ("n", 1, 1),
             ("m", 1, 1), ("comma", 1, 1), ("period", 1, 1), ("slash", 1, 1), ("rshift", 2.75, 1), (nil, 1.25, 1), ("up", 1, 1), (nil, 1.25, 1),
             ("kp1", 1, 1), ("kp2", 1, 1), ("kp3", 1, 1), ("kp_enter", 1, 2)],
            [("m5", 1, 1), (nil, 0.25, 1), ("lctrl", 1.25, 1), ("lwin", 1.25, 1), ("lalt", 1.25, 1), ("space", 6.25, 1), ("ralt", 1.25, 1),
             ("fn", 1.25, 1), ("menu", 1.25, 1), ("rctrl", 1.25, 1), (nil, 0.25, 1), ("left", 1, 1), ("down", 1, 1), ("right", 1, 1), (nil, 0.25, 1),
             ("kp0", 2, 1), ("kp_decimal", 1, 1)],
        ]
        var caps: [Cap] = []
        for (r, row) in rows.enumerated() {
            var x = 0.0
            let y = Double(r) + (r > 0 ? 0.35 : 0)
            for (name, w, h) in row {
                if let n = name { caps.append(Cap(id: n, x: x, y: y, w: w, h: h)) }
                x += w
            }
        }
        // The logo sits below the spacebar on this keyboard.
        caps.append(Cap(id: "logo", x: 6.875, y: 6.5, w: 2.5, h: 0.7))
        return caps
    }()

    static let width = 23.75
    static let height = 7.2

    static let labels: [String: String] = [
        "esc": "Esc", "printscreen": "PrtSc", "scrolllock": "ScrLk", "pause": "Pause", "logo": "◆ Razer logo",
        "grave": "`", "minus": "-", "equal": "=", "backspace": "⌫", "insert": "Ins", "home": "Home", "pageup": "PgUp",
        "numlock": "Num", "kp_divide": "/", "kp_multiply": "*", "kp_minus": "-", "tab": "Tab", "lbracket": "[", "rbracket": "]",
        "backslash": "\\", "delete": "Del", "end": "End", "pagedown": "PgDn", "kp_plus": "+", "capslock": "Caps", "semicolon": ";",
        "quote": "'", "enter": "Enter", "lshift": "Shift", "rshift": "Shift", "comma": ",", "period": ".", "slash": "/",
        "up": "↑", "down": "↓", "left": "←", "right": "→", "kp_enter": "Ent", "lctrl": "Ctrl", "rctrl": "Ctrl", "lwin": "Win",
        "lalt": "Alt", "ralt": "Alt", "fn": "Fn", "menu": "Menu", "space": "", "kp0": "0", "kp_decimal": ".",
        "kp1": "1", "kp2": "2", "kp3": "3", "kp4": "4", "kp5": "5", "kp6": "6", "kp7": "7", "kp8": "8", "kp9": "9",
    ]

    static func label(_ n: String) -> String { labels[n] ?? n.uppercased() }
}

struct KeyboardView: View {
    let colorFor: (String) -> Color?
    @Binding var selection: Set<String>
    var badgeFor: ((String) -> String?)? = nil
    var unit: CGFloat = 28

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(VisualLayout.caps) { cap in
                let selected = selection.contains(cap.id)
                let fill = colorFor(cap.id)
                Button {
                    if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                        if selected { selection.remove(cap.id) } else { selection.insert(cap.id) }
                    } else {
                        selection = selected && selection.count == 1 ? [] : [cap.id]
                    }
                } label: {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(white: 0.13))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(fill ?? Color(white: 0.22))
                            .opacity(fill == nil ? 1 : 0.85)
                            .padding(2)
                        Text(VisualLayout.label(cap.id))
                            .font(.system(size: VisualLayout.label(cap.id).count > 3 ? 8.5 : 10, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: cap.w * unit - 10, alignment: .leading)
                            .foregroundStyle(textColor(fill))
                            .padding(.leading, 5).padding(.top, 3)
                        if let b = badgeFor?(cap.id) {
                            Text(b).font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 3).background(Capsule().fill(Color.accentColor))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(3)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.accentColor : .clear, lineWidth: 2.5))
                    .frame(width: cap.w * unit - 3, height: cap.h * unit - 3)
                }
                .buttonStyle(.plain)
                .help(cap.id)
                .offset(x: cap.x * unit, y: cap.y * unit)
            }
        }
        .frame(width: VisualLayout.width * unit, height: VisualLayout.height * unit, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.07)))
    }

    private func textColor(_ c: Color?) -> Color {
        guard let c else { return Color(white: 0.75) }
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        let lum = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
        return lum > 0.6 ? .black.opacity(0.75) : .white.opacity(0.9)
    }
}
