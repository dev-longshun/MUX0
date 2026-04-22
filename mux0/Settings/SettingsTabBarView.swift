import SwiftUI
import AppKit

/// 只读水平 tab 条 + 右侧 × 关闭按钮。
/// 视觉复刻 TabContent/TabBarView（左侧 strip 含 pills、右侧 28pt 外置按钮），
/// 但交互上：pills 只读、右侧按钮是关闭而非新建。
struct SettingsTabBarView: View {
    let theme: AppTheme
    @Binding var selection: SettingsSection
    let onClose: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.locale) private var locale

    var body: some View {
        let opacity = themeManager.contentEffectiveOpacity
        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: TabBarView.stripRadius, style: .continuous)
                    .fill(Color(theme.sidebar).opacity(opacity))
                HStack(spacing: TabBarView.pillInset) {
                    ForEach(SettingsSection.allCases) { section in
                        pill(for: section)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, TabBarView.pillInset)
            }
            .frame(maxWidth: .infinity)

            IconButton(theme: theme, help: String(localized: (L10n.Settings.close).withLocale(locale)), action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(theme.textSecondary))
            }
            .frame(width: 28)
        }
        .frame(height: TabBarView.height)
    }

    private func pill(for section: SettingsSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            // 固定宽度 / 字号与 TabItemView 对齐：140pt、DT.Font.small、文字左对齐 10pt margin。
            Text(section.label)
                .font(Font(DT.Font.small))
                .foregroundColor(Color(isSelected ? theme.textPrimary : theme.textSecondary))
                .padding(.leading, 10)
                .frame(width: TabBarView.tabItemWidth,
                       height: TabBarView.height - 2 * TabBarView.pillInset,
                       alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: TabBarView.pillRadius, style: .continuous)
                        .fill(Color(isSelected ? theme.canvas : .clear)
                            .opacity(isSelected ? themeManager.contentEffectiveOpacity : 1))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
