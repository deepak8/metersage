import AppKit
import Charts
import SwiftUI
import UsageCore

extension Provider {
    var color: Color {
        switch self { case .codex: UtilityTheme.accent; case .claude: UtilityTheme.adaptive(0x687687, 0xC0CBD8); case .antigravity: UtilityTheme.adaptive(0x263D58, 0x648EBA) }
    }
}

struct DashboardView: View {
    @Bindable var store: MonitorStore
    // Presentation belongs to the persistent dashboard, not the usage store.
    @State private var activeSheet: DashboardSheet?
    @State private var refreshFeedback: String?
    @State private var feedbackTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func refreshManually() {
        guard !store.refreshing, !store.demo else { return }
        feedbackTask?.cancel()
        refreshFeedback = "Refreshing connected providers…"
        Task {
            await store.refresh()
            let health = ProviderHealth(enabled: store.enabled, readings: store.visibleReadings,
                                        messages: store.messages, refreshing: false)
            refreshFeedback = health.status == .healthy ? "Allowances updated" : health.text
            feedbackTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                refreshFeedback = nil
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 20)
            ScrollViewReader { proxy in
              ScrollView {
                VStack(spacing: 12) {
                    if store.demo {
                        HStack(spacing: 6) {
                            Image(systemName: "flask")
                            Text("Demo mode · Sample data")
                            Spacer()
                            Button("Exit demo") { store.demo = false }.buttonStyle(.link)
                        }
                        .font(.caption).foregroundStyle(UtilityTheme.secondary).padding(.bottom, 12)
                    }
                    ForEach(Provider.allCases) { provider in
                        ProviderCard(provider: provider, reading: store.reading(provider),
                                     message: store.demo ? nil : store.messages[provider],
                                     threshold: store.warningThreshold,
                                     connect: { activeSheet = .connection(provider) },
                                     disconnect: { store.disconnect(provider) })
                            .id(provider)
                    }
                    UsageChart(days: store.visibleDays, demo: store.demo, availability: store.historyAvailability, retry: refreshManually)
                        .utilitySurface()
                }.padding(16)
              }
              .onReceive(NotificationCenter.default.publisher(for: .meterSageFocusProvider)) { notification in
                  guard let provider = notification.object as? Provider else { return }
                  withAnimation { proxy.scrollTo(provider, anchor: .top) }
              }
            }
            HStack(spacing: 8) {
                if let refreshFeedback {
                    Image(systemName: store.refreshing ? "arrow.triangle.2.circlepath" : "info.circle")
                    Text(refreshFeedback).lineLimit(1)
                } else {
                    Text("Allowance remaining · 5-hour & weekly")
                }
                Spacer(minLength: 0)
            }.font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                .padding(.horizontal, 20).frame(height: 28)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: refreshFeedback)
            Divider().overlay(UtilityTheme.line)
            footer
        }
        .frame(width: 440, height: min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 70))
        .utilityAppearance()
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .connection(let provider): ConnectionView(provider: provider, store: store)
            case .settings: MonitorSettingsView(store: store)
            case .history: HistoryView(store: store)
            }
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill").font(.title2)
            Text("MeterSage").font(.system(size: 20, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: refreshManually) {
                Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium)).frame(width: 28, height: 28)
                    .opacity(store.refreshing ? 0 : 1)
                    .overlay { if store.refreshing { ProgressView().controlSize(.mini).accessibilityLabel("Refreshing usage") } }
            }.buttonStyle(.plain).help("Refresh usage").disabled(store.demo || store.refreshing)
                .accessibilityLabel("Refresh usage")
            Button { activeSheet = .settings } label: { Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 28, height: 28) }
                .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }
    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let health = ProviderHealth(enabled: store.enabled, readings: store.visibleReadings,
                                        messages: store.messages, refreshing: store.refreshing, now: context.date)
            HStack(spacing: 7) {
                Circle().fill(store.demo ? Color.orange : (health.status == .healthy ? UtilityTheme.accent : (health.status == .attention ? UtilityTheme.warning : UtilityTheme.secondary)))
                    .frame(width: 8, height: 8).accessibilityHidden(true)
                if !store.demo, let provider = health.recoveryProvider {
                    Button { activeSheet = .connection(provider) } label: {
                        HStack(spacing: 3) { Text(health.text); Image(systemName: "chevron.right") }
                    }.buttonStyle(.plain).font(.callout)
                        .help("Check \(provider.name) connection")
                        .accessibilityLabel("\(health.text). Check \(provider.name) connection")
                } else {
                    Text(store.demo ? "Illustrative data" : health.text).font(.callout).foregroundStyle(UtilityTheme.secondary)
                }
                Spacer(minLength: 8)
                Button { activeSheet = .history } label: {
                    HStack(spacing: 4) { Text("View history"); Image(systemName: "chevron.right") }
                }.buttonStyle(.link).font(.callout)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
}

private enum DashboardSheet: Identifiable {
    case connection(Provider)
    case settings
    case history

    var id: String {
        switch self {
        case .connection(let provider): "connection-\(provider.rawValue)"
        case .settings: "settings"
        case .history: "history"
        }
    }
}

struct ProviderMark: View {
    let provider: Provider
    var body: some View {
        Image(nsImage: ProviderIcons.image(for: provider))
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: 28, height: 28).accessibilityHidden(true)
    }
}

struct ProviderCard: View {
    let provider: Provider
    let reading: Reading?
    let message: String?
    let threshold: Double
    let connect: () -> Void
    let disconnect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ProviderMark(provider: provider).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name + (reading?.plan.map { " · " + $0 } ?? ""))
                        .font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(reading?.account ?? (reading == nil ? "Not connected" : "Official CLI"))
                        .font(.callout).foregroundStyle(UtilityTheme.secondary).lineLimit(1).truncationMode(.middle)
                        .help(reading?.account ?? "Signed in through the official CLI")
                }
                Spacer(minLength: 0)
                if let reading {
                    HStack(alignment: .center, spacing: 4) {
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text((reading.isStale() ? "Cached " : "Updated ") + ReportAge.compact(reading.observedAt))
                                .help(reading.observedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.callout).foregroundStyle(UtilityTheme.secondary)
                        }
                        Menu {
                            Button("Reconnect…", systemImage: "arrow.clockwise", action: connect)
                            Button("Disconnect", systemImage: "link", action: disconnect)
                        } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("\(provider.name) account actions")
                    }
                }
            }
            if let reading {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let windows = AllowanceWindow.allCases
                    let tightest = windows.filter { reading.quota(for: $0, at: context.date) != nil }
                        .min { reading.quota(for: $0, at: context.date)!.remaining < reading.quota(for: $1, at: context.date)!.remaining }
                    let remainingValues = Set(windows.compactMap { reading.quota(for: $0, at: context.date)?.remaining })
                    VStack(spacing: 12) {
                        ForEach(windows) { window in
                            quotaRow(reading.quota(for: window, at: context.date), title: window.title,
                                     stale: reading.isStale(at: context.date), tightest: window == tightest && remainingValues.count > 1,
                                     now: context.date, showGroup: provider == .antigravity)
                        }
                    }
                }
                if provider == .antigravity {
                    DisclosureGroup("Model groups (\(reading.quotas.count))") {
                        VStack(spacing: 12) {
                            ForEach(Array(reading.quotas.enumerated()), id: \.offset) { _, quota in
                                quotaRow(quota, title: quota.label, stale: reading.isStale(), tightest: false,
                                         now: .now, showGroup: false)
                            }
                        }.padding(.top, 8)
                    }.font(.callout)
                }
                DisclosureGroup(provider == .claude ? "Session & source details" : "Usage details") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array((reading.unavailableQuotas ?? []).enumerated()), id: \.offset) { _, label in
                            Label(label + ": Unavailable", systemImage: "questionmark.circle")
                                .font(.callout).foregroundStyle(UtilityTheme.secondary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "cylinder.split.1x2").font(.title3).frame(width: 24)
                            Text(provider == .claude ? "Current context tokens" : (provider == .codex ? "Today’s reported tokens" : "Token activity"))
                                .foregroundStyle(UtilityTheme.secondary)
                            Spacer()
                            Text(reading.tokens.map { $0.formatted() } ?? "Unavailable").fontWeight(.semibold)
                        }.font(.callout)
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "tag").frame(width: 24)
                            Text(provider == .claude ? "CLI session cost estimate: " : "Estimated API-equivalent cost: ") + Text(reading.estimatedCost.map { "~" + $0.formatted(.currency(code: "USD")) } ?? "Unavailable")
                        }.font(.callout).foregroundStyle(UtilityTheme.secondary)
                        if provider == .claude {
                            Text("Session estimate, not subscription spending.").font(.callout).foregroundStyle(UtilityTheme.secondary)
                        }
                        if !reading.scope.hasPrefix("Sample data") {
                            Text(reading.scope).font(.callout).foregroundStyle(UtilityTheme.secondary)
                        }
                        if provider == .claude, let captured = reading.metricsObservedAt {
                            Text("Context / session cost reported \(captured, style: .relative) ago · latest CLI session")
                                .font(.callout).foregroundStyle(UtilityTheme.secondary)
                        }
                    }.padding(.top, 8)
                }.font(.callout)
                if provider == .claude && reading.isStale() {
                    Label("Last known allowance. Refresh requests an updated account report from Claude Code.", systemImage: "clock")
                        .font(.callout).foregroundStyle(UtilityTheme.warning)
                }
                if let message { Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(UtilityTheme.failure) }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Text(message ?? "Connect to track your \(provider.name) usage and allowances.")
                        .font(.callout).foregroundStyle(UtilityTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Sign in", action: connect).utilityPrimaryAction().controlSize(.large)
                }
            }
        }.utilitySurface()
    }
    private func quotaRow(_ quota: Quota?, title: String, stale: Bool, tightest: Bool,
                          now: Date, showGroup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.body.weight(.medium))
                if tightest {
                    Text("Tightest").font(.system(size: 12)).foregroundStyle(UtilityTheme.secondary)
                }
                Spacer(minLength: 4)
                Text(quota.map { "\(Int($0.remaining))% " + (stale ? "last reported" : "remaining") } ?? "Unavailable")
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(stale ? UtilityTheme.secondary : UtilityTheme.ink)
            }
            if let quota {
                allowanceBar(quota, stale: stale, height: 6)
                HStack(alignment: .top, spacing: 8) {
                    if showGroup {
                        Text(quota.label.components(separatedBy: " · ").dropLast().joined(separator: " · "))
                    }
                    if let reset = quota.resetsAt {
                        Text(reset > now ? "Resets in \(reset.timeIntervalSince(now).countdown)" : "Awaiting reset")
                    } else if let description = quota.resetDescription {
                        Text(description)
                    }
                    Spacer(minLength: 0)
                    if !stale && quota.remaining <= threshold {
                        Label(quota.remaining == 0 ? "Exhausted" : "Low allowance", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(UtilityTheme.warning)
                    }
                }.font(.callout).foregroundStyle(UtilityTheme.secondary)
            }
        }
    }
    private func allowanceBar(_ quota: Quota, stale: Bool, height: CGFloat) -> some View {
        GeometryReader { geometry in
            Capsule().fill(UtilityTheme.track)
                .overlay(alignment: .leading) {
                    Capsule().fill(stale ? UtilityTheme.secondary : (quota.remaining <= threshold ? UtilityTheme.warning : UtilityTheme.meter))
                        .frame(width: max(0, geometry.size.width * quota.remaining / 100))
                }
        }.frame(height: height)
            .accessibilityLabel("\(quota.label): \(Int(quota.remaining)) percent remaining")
    }
}

struct UsageChart: View {
    let days: [UsageDay]
    let demo: Bool
    var availability: HistoryAvailability? = nil
    var retry: (() -> Void)? = nil
    private var recent: [UsageDay] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))!
        return days.filter { $0.date >= start && $0.date <= .now }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("7-Day Usage").font(.system(size: 14, weight: .semibold))
                Spacer()
                if !recent.isEmpty {
                    Text(recent.reduce(0) { $0 + $1.tokens }.formatted(.number.notation(.compactName)) + " tokens")
                        .font(.callout).fontWeight(.semibold)
                }
            }
            if recent.isEmpty {
                let state = availability ?? HistoryAvailability(enabled: [], codexState: .notReported, refreshing: false)
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.title).font(.callout.weight(.medium))
                    Text(state.detail).font(.callout).foregroundStyle(UtilityTheme.secondary)
                    if state.canRetry, let retry {
                        Button("Retry report", action: retry).buttonStyle(.link).font(.callout)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(recent) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Tokens", day.tokens), width: .ratio(0.65))
                        .foregroundStyle(by: .value("Provider", day.provider.name))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(
                    domain: Provider.allCases.filter { provider in recent.contains { $0.provider == provider } }.map(\.name),
                    range: Provider.allCases.filter { provider in recent.contains { $0.provider == provider } }.map(\.color)
                )
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let n = value.as(Int.self) { Text(n.formatted(.number.notation(.compactName))) } }
                } }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
                .frame(height: 120)
            }
            if !recent.isEmpty {
                Text(demo ? "Sample daily totals · amounts are illustrative" : "Reported daily tokens · coverage varies by provider")
                    .font(.callout).foregroundStyle(UtilityTheme.secondary)
            }
        }
    }
}

private extension TimeInterval {
    var countdown: String {
        let minutes = max(1, Int(self) / 60)
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
