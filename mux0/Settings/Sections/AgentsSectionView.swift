import SwiftUI

struct AgentsSectionView: View {
    let theme: AppTheme
    let settings: SettingsConfigStore

    /// All config keys this section manages. Data-driven from `HookMessage.Agent.allCases`
    /// so adding a new agent (enum case) auto-registers it with the reset button.
    private static let managedKeys: [String] = HookMessage.Agent.allCases.map(\.settingsKey)

    /// Codex hooks are gated behind an experimental flag (`[features].codex_hooks = true`
    /// in `~/.codex/config.toml`). The wrapper can't flip it for the user — the flag
    /// must live in the user's main config. See docs/agent-hooks.md.
    @State private var showingCodexAlert = false
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            ForEach(HookMessage.Agent.allCases) { agent in
                AgentToggleRow(
                    theme: theme,
                    settings: settings,
                    agent: agent,
                    onTurnOn: agent == .codex ? { showingCodexAlert = true } : nil
                )
            }
            SettingsResetRow(settings: settings, keys: Self.managedKeys)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert(
            String(localized: L10n.Settings.Agents.codexAlertTitle.withLocale(locale)),
            isPresented: $showingCodexAlert
        ) {
            Button(String(localized: L10n.Settings.Agents.codexAlertOK.withLocale(locale))) { }
        } message: {
            Text(L10n.Settings.Agents.codexAlertMessage)
        }
    }
}

/// One row per agent: label + BETA badge + trailing toggle.
/// When `onTurnOn` is provided, it fires once on each false→true transition
/// (used by Codex to surface the experimental-flag alert).
private struct AgentToggleRow: View {
    let theme: AppTheme
    let settings: SettingsConfigStore
    let agent: HookMessage.Agent
    let onTurnOn: (() -> Void)?

    var body: some View {
        LabeledContent {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
        } label: {
            HStack(spacing: DT.Space.sm) {
                Text(agent.label)
                BetaBadge(theme: theme)
            }
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: {
                guard let raw = settings.get(agent.settingsKey) else { return false }
                return raw.lowercased() == "true"
            },
            set: { newValue in
                let wasOn = settings.get(agent.settingsKey)?.lowercased() == "true"
                settings.set(agent.settingsKey, newValue ? "true" : nil)
                if newValue && !wasOn { onTurnOn?() }
            }
        )
    }
}

private struct BetaBadge: View {
    let theme: AppTheme

    var body: some View {
        Text(L10n.Settings.Agents.betaBadge)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color(theme.accent))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color(theme.accent).opacity(0.6), lineWidth: 1)
            )
    }
}
