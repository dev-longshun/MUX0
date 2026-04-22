import Foundation

/// 设置视图的六个硬编码分类。顺序即 tab 条显示顺序，不可重排。
enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case font
    case terminal
    case shell
    case agents
    case update

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .appearance: return L10n.Settings.sectionAppearance
        case .font:       return L10n.Settings.sectionFont
        case .terminal:   return L10n.Settings.sectionTerminal
        case .shell:      return L10n.Settings.sectionShell
        case .agents:     return L10n.Settings.sectionAgents
        case .update:     return L10n.Settings.sectionUpdate
        }
    }
}
