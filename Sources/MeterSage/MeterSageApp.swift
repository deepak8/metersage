import AppKit
import SwiftUI

@main @MainActor struct Launcher {
    static func main() {
        if CommandLine.arguments.contains("--claude-statusline") {
            do { try LocalFiles.receiveStatusline() } catch { exit(1) }
        } else if CommandLine.arguments.contains("--probe-claude") {
            do {
                guard let executable = LocalFiles.executable("claude") else { throw CommandFailure.launchFailed }
                let reading = try ClaudeUsageProbe.readSynchronously(executable: executable)
                print(String(decoding: try JSONEncoder().encode(reading), as: UTF8.self))
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--probe-antigravity") {
            do {
                guard let executable = LocalFiles.executable("agy") else { throw CommandFailure.launchFailed }
                let reading = try AntigravityIntegration.readSynchronously(executable: executable)
                print(String(decoding: try JSONEncoder().encode(reading), as: UTF8.self))
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        } else if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
            SnapshotRenderer.render(to: CommandLine.arguments[index + 1])
        } else {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let delegate = MonitorAppDelegate()
            application.delegate = delegate
            withExtendedLifetime(delegate) { application.run() }
        }
    }
}

/// Menu-bar utilities still need a visible response to launch and Finder/Open
/// requests, including when the menu bar item is hidden behind a laptop notch.
@MainActor final class MonitorAppDelegate: NSObject, NSApplicationDelegate {
    private var dashboardWindow: NSWindow?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(store: .shared, openDashboard: { [weak self] provider in
            self?.showDashboard()
            if let provider {
                NotificationCenter.default.post(name: .meterSageFocusProvider, object: provider)
            }
        })
        DispatchQueue.main.async { self.showDashboard() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.invalidate()
    }

    private func showDashboard() {
        if dashboardWindow == nil {
            let store = MonitorStore.shared
            let content = DashboardWindowView(store: store)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 70)),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "MeterSage"
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(UtilityTheme.canvas)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: content)
            window.center()
            dashboardWindow = window
        }
        dashboardWindow?.deminiaturize(nil)
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct DashboardWindowView: View {
    @Bindable var store: MonitorStore
    var body: some View {
        DashboardView(store: store)
            .preferredColorScheme(store.appearance == "system" ? nil : (store.appearance == "dark" ? .dark : .light))
            .onAppear { syncWindowAppearance() }
            .onChange(of: store.appearance) { _, _ in syncWindowAppearance() }
    }
    private func syncWindowAppearance() {
        NSApplication.shared.windows.first { $0.title == "MeterSage" }?.appearance =
            store.appearance == "system" ? nil : NSAppearance(named: store.appearance == "dark" ? .darkAqua : .aqua)
    }
}

@MainActor enum SnapshotRenderer {
    static func render(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = MonitorStore(startAutomatically: false)
        store.enabled = []
        store.demo = true
        let dark = CommandLine.arguments.contains("--dark")
        let root: AnyView
        let size: CGSize
        if CommandLine.arguments.contains("--settings") {
            root = AnyView(MonitorSettingsView(store: store)); size = CGSize(width: 430, height: 620)
        } else if CommandLine.arguments.contains("--history") {
            root = AnyView(HistoryView(store: store)); size = CGSize(width: 430, height: 540)
        } else if CommandLine.arguments.contains("--connection") {
            store.demo = false
            root = AnyView(ConnectionView(provider: .claude, store: store)); size = CGSize(width: 430, height: 540)
        } else {
            root = AnyView(DashboardView(store: store)); size = CGSize(width: 440, height: 820)
        }
        let view = NSHostingView(rootView: root.background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(dark ? .dark : .light).tint(UtilityTheme.accent))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if CommandLine.arguments.contains("--connection") {
                window.setContentSize(NSSize(width: 430, height: view.fittingSize.height))
                view.layoutSubtreeIfNeeded()
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try data.write(to: URL(fileURLWithPath: path)); exit(0) } catch { exit(1) }
        }
        app.run()
    }
}
