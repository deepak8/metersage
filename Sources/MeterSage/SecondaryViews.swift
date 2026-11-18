import AppKit
import ServiceManagement
import SwiftUI
import UsageCore

struct ConnectionView: View {
    let provider: Provider
    @Bindable var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    @State private var notice: String?
    @State private var copied = false
    private var cliName: String { LocalFiles.cliName(for: provider) }
    private var installURL: URL {
        let address = switch provider {
        case .codex: "https://developers.openai.com/codex/cli"
        case .claude: "https://code.claude.com/docs/en/quickstart"
        case .antigravity: "https://antigravity.google/docs/getting-started"
        }
        return URL(string: address)!
    }
    private var installed: Bool { LocalFiles.executable(cliName) != nil }
    private var bridgeCommand: String {
        LocalFiles.shellQuote(Bundle.main.executableURL!.path) + " --claude-statusline"
    }
    private var bridgeJSON: String {
        let object: [String: Any] = ["statusLine": ["type": "command", "command": bridgeCommand]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderMark(provider: provider)
                Text("Connect \(provider.name)").font(.system(size: 18, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).help("Close setup").accessibilityLabel("Close connection setup")
            }.padding(20)
            Divider().overlay(UtilityTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.demo {
                        Label("You’re viewing sample data", systemImage: "flask").foregroundStyle(UtilityTheme.warning)
                        Text("Exit demo mode to connect a real account. Demo actions do not change your provider sessions.")
                            .foregroundStyle(UtilityTheme.secondary)
                        Button("Exit demo mode") { store.demo = false; dismiss() }.utilityPrimaryAction()
                    } else {
                        Text("Sign in with your subscription through the official \(provider.name) CLI. Your credentials stay with that client.")
                            .foregroundStyle(UtilityTheme.secondary)
                        Label(installed ? "Official CLI found" : "Official CLI not found", systemImage: installed ? "checkmark.circle" : "arrow.down.circle")
                            .font(.callout).foregroundStyle(installed ? UtilityTheme.accent : UtilityTheme.warning)
                        if installed {
                            Button("Open official sign-in…") {
                                notice = LocalFiles.openLogin(provider) ? "Sign-in opened in Terminal. Finish there, then check the connection below." : "Could not open Terminal. Use the official CLI to sign in."
                            }.utilityPrimaryAction().controlSize(.large)
                            Text("Opens Terminal and may open your browser. Signing in can change the account used by your official CLI.")
                                .font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                        } else {
                            Link("Install the official \(provider.name) CLI", destination: installURL)
                            Text("Supported locations: ~/.local/bin, /opt/homebrew/bin, /usr/local/bin, or this app’s PATH. Reopen this setup after installing.")
                                .font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                        }
                        if provider == .claude {
                            Divider()
                            Text("Account allowance updates automatically through Claude Code’s /usage command, including usage from Claude Desktop and web on the same account. No CLI message is needed.")
                                .font(.callout).foregroundStyle(UtilityTheme.secondary)
                            DisclosureGroup("Optional: context tokens and session cost") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("After signing in, merge this statusLine entry into ~/.claude/settings.json. Keep any existing settings. If you already have a status line, chain this command with yours instead of replacing it.")
                                        .font(.callout).foregroundStyle(UtilityTheme.secondary)
                                    Text(bridgeJSON).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(UtilityTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                                    Button(copied ? "Copied JSON" : "Copy bridge configuration") {
                                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(bridgeJSON, forType: .string)
                                        copied = true; notice = "Bridge configuration copied."
                                    }
                                    Text("Keep the app at the same path after setup. Start or resume a Claude Code session to send a reading. Only numeric metrics and a session identifier are stored locally; prompts and credentials are excluded. Account allowance is fetched separately.")
                                        .font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                                }.padding(.top, 8)
                            }
                        }
                        if provider == .antigravity {
                            Divider()
                            Text("Connect account quotas").font(.headline)
                            Text("Finish the official CLI setup, then click Check connection. MeterSage reads Gemini and Claude/GPT quota groups through agy’s usage report. No status-line configuration is required.")
                                .font(.callout).foregroundStyle(UtilityTheme.secondary)
                            Text("Refresh requests a new report without sending a model prompt. Quotas remain separate from your direct Codex and Claude subscriptions. Token activity and costs are unavailable from this report.")
                                .font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                            Text("Requires Antigravity CLI 1.1.11 or later.").font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                        }
                        Text(notice ?? "").font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                            .lineLimit(3).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        if let error = store.messages[provider] {
                            Label(error, systemImage: "info.circle").font(.callout).foregroundStyle(UtilityTheme.failure)
                        }
                        if let reading = store.reading(provider) {
                            Label(reading.isStale() ? "Keeping the last reading; waiting for fresh usage" : "Usage connection verified", systemImage: "checkmark.circle")
                                .font(.callout).foregroundStyle(reading.isStale() ? UtilityTheme.warning : UtilityTheme.accent)
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(UtilityTheme.line)
            HStack(spacing: 12) {
                if !store.demo {
                    Button("Check connection") { store.connect(provider) }
                        .utilityPrimaryAction().disabled(!installed || store.refreshing)
                    ZStack { if store.refreshing { ProgressView().controlSize(.small).accessibilityLabel("Checking connection") } }.frame(width: 16, height: 16)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
        }.frame(width: 430, height: min(provider == .codex ? 420 : 540, (NSScreen.main?.visibleFrame.height ?? 900) - 120))
            .utilityAppearance()
    }
}

struct MonitorSettingsView: View {
    @Bindable var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    @State private var confirmingDelete = false
    var body: some View {
        VStack(spacing: 0) {
            UtilitySheetHeader(title: "Settings", dismiss: { dismiss() }).padding(20)
            Form {
                Section("General") {
                    Picker("Appearance", selection: $store.appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, new in
                        do { if new { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { self.error = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                    }
                    Picker("Refresh", selection: $store.refreshMinutes) {
                        Text("Every minute").tag(1); Text("Every 5 minutes").tag(5); Text("Every 15 minutes").tag(15)
                    }
                    Text("Fetches account allowances for all connected providers. Claude session metrics follow CLI activity.").font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                }
                Section("Low-allowance alerts") {
                    Toggle("Send notifications", isOn: Binding(get: { store.notifications }, set: { new in
                        if new { Task { await store.requestNotifications() } } else { store.notifications = false }
                    }))
                    Picker("Warning threshold", selection: $store.warningThreshold) {
                        Text("10% remaining").tag(10.0); Text("20% remaining").tag(20.0); Text("30% remaining").tag(30.0)
                    }
                    Text("Also warns at 10%. Stale readings and demo data do not trigger alerts.").font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                }
                Section("Preview & data") {
                    Toggle("Demo mode", isOn: $store.demo)
                    Text("Demo mode shows sample accounts and amounts. Live connection actions are disabled.").font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                    Button("Delete local bridge data…", role: .destructive) { confirmingDelete = true }
                    Text("Provider-reported history may return on refresh. Deleting bridge data does not change your CLI configuration.").font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(UtilityTheme.warning) }
                Section {
                    HStack { Text("MeterSage 0.1.0").foregroundStyle(UtilityTheme.secondary); Spacer(); Button("Quit") { NSApplication.shared.terminate(nil) } }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
        }.frame(width: 430, height: 620).utilityAppearance()
            .alert("Delete local bridge data?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { store.clearLocalHistory() }
            } message: { Text("Claude Code can send new metrics while its bridge remains configured.") }
    }
}

struct HistoryView: View {
    @Bindable var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UtilitySheetHeader(title: "Usage history", dismiss: { dismiss() })
            if store.demo { Label("Sample history", systemImage: "flask").font(.system(size: 12)).foregroundStyle(UtilityTheme.warning) }
            UsageChart(days: store.visibleDays, demo: store.demo, availability: store.historyAvailability, retry: { Task { await store.refresh() } })
            Divider()
            if !store.visibleDays.isEmpty {
                List(store.visibleDays.sorted { $0.date > $1.date }) { day in
                    HStack {
                        Circle().fill(day.provider.color).frame(width: 7, height: 7)
                        Text(day.provider.name)
                        Text(day.date, format: .dateTime.month(.abbreviated).day()).foregroundStyle(UtilityTheme.secondary)
                        Spacer()
                        Text(day.tokens.formatted() + " tokens").monospacedDigit()
                    }.font(.callout)
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
            Text("Only provider-reported daily totals are included. Token amounts from different providers do not imply equal cost.")
                .font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
        }.padding(24).frame(width: 430, height: store.visibleDays.isEmpty ? 300 : 540).utilityAppearance()
    }
}
