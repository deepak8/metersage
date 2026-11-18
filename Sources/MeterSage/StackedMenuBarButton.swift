import AppKit
import UsageCore

/// A normal NSButton owns mouse/keyboard interaction. Only its presentation is
/// custom: two explicitly labeled windows within the native 22-point strip.
@MainActor final class StackedMenuBarButton: NSButton {
    static let columnWidth: CGFloat = 72
    private(set) var weekly: MenuBarLimitSummary?
    private(set) var fiveHour: MenuBarLimitSummary?
    private var connectionWarning = false
    override var isFlipped: Bool { true }

    func update(weekly: MenuBarLimitSummary, fiveHour: MenuBarLimitSummary, connectionWarning: Bool) {
        self.weekly = weekly
        self.fiveHour = fiveHour
        self.connectionWarning = connectionWarning
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var warningColor: NSColor {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? NSColor(srgbRed: 0.914, green: 0.733, blue: 0.439, alpha: 1)
            : NSColor(srgbRed: 0.580, green: 0.337, blue: 0.031, alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let top = (bounds.height - 22) / 2
        image?.draw(in: NSRect(x: 1, y: top + 3, width: 16, height: 16), from: .zero,
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        drawRow(label: "W", value: weekly, y: top)
        drawRow(label: "5h", value: fiveHour, y: top + 11)
        if connectionWarning {
            warningColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14, y: top + 16, width: 4, height: 4)).fill()
        }
        if window?.firstResponder === self, NSApp.isFullKeyboardAccessEnabled {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawRow(label: String, value: MenuBarLimitSummary?, y: CGFloat) {
        let color: NSColor
        switch value?.tone {
        case .low: color = warningColor
        case .normal: color = .labelColor
        default: color = .secondaryLabelColor
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (label as NSString).draw(at: NSPoint(x: 23, y: y + 0.5), withAttributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .regular), .foregroundColor: dark ? NSColor.white : NSColor.labelColor
        ])
        ((value?.text ?? "—") as NSString).draw(at: NSPoint(x: 38, y: y), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium), .foregroundColor: color
        ])
    }
}
