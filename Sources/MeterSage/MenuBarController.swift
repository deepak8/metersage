import AppKit
import Observation
import UsageCore

@MainActor enum ProviderIcons {
    private static var cached: [Provider: NSImage] = [:]

    static func image(for provider: Provider) -> NSImage {
        if let image = cached[provider] { return image }
        // Use the user's installed app artwork without redistributing vendor
        // icon files in this repository or in MeterSage's app bundle.
        let names: [String] = switch provider {
        case .codex: ["Codex.app", "ChatGPT.app"]
        case .claude: ["Claude.app"]
        case .antigravity: ["Antigravity IDE.app", "Antigravity.app"]
        }
        let directories = [URL(fileURLWithPath: "/Applications"),
                           FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        let installed = directories.flatMap { directory in names.map { directory.appendingPathComponent($0) } }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        let image = installed.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? fallback(for: provider)
        cached[provider] = image
        return image
    }

    static func fallback(for provider: Provider) -> NSImage {
        let mark = switch provider { case .codex: "Co"; case .claude: "Cl"; case .antigravity: "Ag" }
        return NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.labelColor]
            let size = (mark as NSString).size(withAttributes: attributes)
            (mark as NSString).draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2), withAttributes: attributes)
            return true
        }
    }
}

extension Notification.Name {
    static let meterSageFocusProvider = Notification.Name("MeterSage.focusProvider")
}

/// One status item keeps all providers and Refresh together. Native child
/// buttons own their clicks; data updates never recreate the item or its window.
@MainActor final class MenuBarController: NSObject {
    private let store: MonitorStore
    private let openDashboard: (Provider?) -> Void
    private let refreshUsage: @MainActor () async -> Void
    private let item: NSStatusItem
    private let strip = NSStackView()
    private let demoLabel = NSTextField(labelWithString: "DEMO")
    private(set) var providerButtons: [Provider: NSButton] = [:]
    private(set) var refreshButton = NSButton()
    private var ageTimer: Timer?

    init(store: MonitorStore, openDashboard: @escaping (Provider?) -> Void,
         refreshUsage: (@MainActor () async -> Void)? = nil) {
        self.store = store
        self.openDashboard = openDashboard
        self.refreshUsage = refreshUsage ?? { await store.refresh() }
        self.item = NSStatusBar.system.statusItem(withLength: 269)
        super.init()
        configure()
        observeChanges()
        ageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    private func configure() {
        guard let container = item.button else { return }
        container.title = ""
        container.setAccessibilityLabel("MeterSage provider usage")
        strip.orientation = .horizontal
        strip.alignment = .centerY
        strip.spacing = 5
        strip.detachesHiddenViews = true
        strip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            strip.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -5),
            strip.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        demoLabel.font = .systemFont(ofSize: 8, weight: .bold)
        demoLabel.textColor = .secondaryLabelColor
        demoLabel.setAccessibilityLabel("Demo data")
        strip.addArrangedSubview(demoLabel)

        for (index, provider) in Provider.allCases.enumerated() {
            let button = StackedMenuBarButton(title: "", target: self, action: #selector(providerClicked))
            button.tag = index
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.image = ProviderIcons.image(for: provider).copy() as? NSImage
            button.image?.size = NSSize(width: 18, height: 18)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.alignment = .center
            let width = button.widthAnchor.constraint(equalToConstant: StackedMenuBarButton.columnWidth)
            NSLayoutConstraint.activate([
                width,
                button.heightAnchor.constraint(equalToConstant: 22)
            ])
            strip.addArrangedSubview(button)
            providerButtons[provider] = button
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
        strip.addArrangedSubview(separator)

        refreshButton.isBordered = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        refreshButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        refreshButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        refreshButton.setAccessibilityLabel("Refresh all provider usage")
        strip.addArrangedSubview(refreshButton)
        container.setAccessibilityRole(.group)
        container.setAccessibilityChildren(Provider.allCases.compactMap { providerButtons[$0] } + [refreshButton])
    }

    private func observeChanges() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeChanges() }
        }
    }

    private func render() {
        demoLabel.isHidden = !store.demo
        for provider in Provider.allCases {
            let summary = MenuBarSummary(provider: provider, reading: store.reading(provider),
                                         error: store.demo ? nil : store.messages[provider], threshold: store.warningThreshold)
            let button = providerButtons[provider] as? StackedMenuBarButton
            let reading = store.reading(provider)
            button?.update(
                weekly: MenuBarLimitSummary(provider: provider, window: .weekly, reading: reading, threshold: store.warningThreshold),
                fiveHour: MenuBarLimitSummary(provider: provider, window: .fiveHour, reading: reading, threshold: store.warningThreshold),
                connectionWarning: !store.demo && (store.messages[provider] != nil || reading?.isStale() == true))
            let description = (store.demo ? "Demo · " : "") + summary.explanation
            button?.toolTip = description + "\nClick to open the dashboard."
            button?.setAccessibilityLabel(description)
        }
        // Three provider buttons, separator, Refresh, four gaps, and insets.
        item.length = StackedMenuBarButton.columnWidth * CGFloat(Provider.allCases.count) + 53
            + (store.demo ? ceil(demoLabel.intrinsicContentSize.width) + 5 : 0)
        refreshButton.image = NSImage(systemSymbolName: store.refreshing ? "hourglass" : "arrow.clockwise", accessibilityDescription: nil)
        refreshButton.isEnabled = !store.refreshing && !store.demo
        refreshButton.toolTip = store.demo ? "Refresh is unavailable for sample data" : (store.refreshing ? "Refreshing usage…" : "Refresh all provider account allowances")
    }

    @objc private func providerClicked(_ sender: NSButton) {
        guard Provider.allCases.indices.contains(sender.tag) else { return }
        openDashboard(Provider.allCases[sender.tag])
    }

    @objc private func refreshClicked(_ sender: NSButton) {
        Task { await refreshUsage() }
    }

    func invalidate() {
        ageTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(item)
    }
}
