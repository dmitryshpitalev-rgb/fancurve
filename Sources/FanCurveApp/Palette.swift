import AppKit
import SwiftUI

/// Colours with a job: status for the mode line and errors — always with an icon and a text, never
/// alone — and the card behind tiles and charts (#ffffff light, #1e1e1e dark; the chart line
/// colours were chosen against both).
enum Palette {
    static let good = Color(hex: 0x0ca30c)
    static let critical = Color(hex: 0xd03b3b)
    static let card = Color(nsColor: .controlBackgroundColor)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}
