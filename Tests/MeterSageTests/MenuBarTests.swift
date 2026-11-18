import AppKit
import Testing
import UsageCore
@testable import MeterSage

@Test @MainActor func nativeMenuBarControlsRouteProviderClicksAndRefreshIndependently() async {
    _ = NSApplication.shared
    let store = MonitorStore(startAutomatically: false)
    store.readings = Provider.allCases.map { provider in
        Reading(provider: provider, quotas: [.init(label: "Weekly", usedPercent: 13), .init(label: "5-hour", usedPercent: 2)], scope: "test")
    }
    var opened: [Provider] = []
    var refreshes = 0
    let controller = MenuBarController(store: store, openDashboard: { provider in
        if let provider { opened.append(provider) }
    }, refreshUsage: { refreshes += 1 })
    defer { controller.invalidate() }

    for provider in Provider.allCases {
        let button = controller.providerButtons[provider] as? StackedMenuBarButton
        #expect(button?.weekly?.text == "87%")
        #expect(button?.fiveHour?.text == "98%")
        #expect(button?.toolTip?.contains("Weekly: 87%") == true)
        controller.providerButtons[provider]?.performClick(nil)
    }
    #expect(opened == Provider.allCases)
    #expect(refreshes == 0)
    controller.refreshButton.performClick(nil)
    for _ in 0..<20 {
        if refreshes == 1 { break }
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(refreshes == 1)
    #expect(opened.count == 3)
    for provider in Provider.allCases {
        #expect(!ProviderIcons.image(for: provider).representations.isEmpty)
        #expect(ProviderIcons.fallback(for: provider).tiffRepresentation != nil)
    }
}

@Test @MainActor func stackedMenuBarKeepsWidthStableAtMaximumAndCachedValues() throws {
    _ = NSApplication.shared
    let button = StackedMenuBarButton(title: "", target: nil, action: nil)
    button.frame = NSRect(x: 0, y: 0, width: StackedMenuBarButton.columnWidth, height: 22)
    let now = Date()
    let reading = Reading(provider: .claude, quotas: [.init(label: "Weekly", usedPercent: 0)], observedAt: now.addingTimeInterval(-1800), scope: "test")
    let cached = MenuBarLimitSummary(provider: .claude, window: .weekly, reading: reading, now: now)
    #expect(cached.text == "100%*")
    let width = (cached.text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)]).width
    #expect(38 + width <= StackedMenuBarButton.columnWidth)
    button.update(weekly: cached, fiveHour: .init(provider: .claude, window: .fiveHour, reading: nil), connectionWarning: true)
    #expect(button.frame.width == 72 && button.frame.height == 22)
}
