import AppKit
import SwiftUI

/// Shared semantic colors. The dynamic provider also follows appearance changes
/// inside native sheets and menus, without persisting another theme preference.
enum UtilityTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let canvas = adaptive(0xF3F5F8, 0x151A21)
    static let surface = adaptive(0xFFFFFF, 0x1E2530)
    static let raised = adaptive(0xE8EDF3, 0x2A3442)
    static let ink = adaptive(0x202D3C, 0xE8EEF6)
    static let secondary = adaptive(0x596879, 0xA9B7C9)
    static let accent = adaptive(0x426D98, 0x99BBDD)
    static let buttonFill = adaptive(0x426D98, 0x426D98)
    static let meter = adaptive(0x587FA7, 0x89AACE)
    static let track = adaptive(0xE4EAF1, 0x354253)
    static let line = adaptive(0xDCE3EC, 0x354152)
    static let warning = adaptive(0x945608, 0xE9BB70)
    static let failure = adaptive(0xAA3A40, 0xF0A1A5)
    static let radius: CGFloat = 12
    static let cardPadding: CGFloat = 16
}

private struct UtilitySurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(UtilityTheme.cardPadding)
            .background(UtilityTheme.surface, in: RoundedRectangle(cornerRadius: UtilityTheme.radius))
            .overlay { RoundedRectangle(cornerRadius: UtilityTheme.radius).strokeBorder(UtilityTheme.line.opacity(0.55), lineWidth: 0.5) }
    }
}

extension View {
    func utilitySurface() -> some View { modifier(UtilitySurface()) }
    func utilityPrimaryAction() -> some View {
        buttonStyle(.borderedProminent).tint(UtilityTheme.buttonFill).foregroundStyle(.white)
    }
    func utilityAppearance() -> some View {
        foregroundStyle(UtilityTheme.ink).tint(UtilityTheme.accent).background(UtilityTheme.canvas)
    }
}

struct UtilitySheetHeader: View {
    let title: String
    let dismiss: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.system(size: 18, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done", action: dismiss).keyboardShortcut(.cancelAction).controlSize(.regular)
        }
    }
}
