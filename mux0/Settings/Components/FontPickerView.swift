import SwiftUI
import AppKit

/// 等宽字体下拉 + "Custom…" 模式。绑 SettingsConfigStore 的 `font-family`。
struct FontPickerView: View {
    let settings: SettingsConfigStore
    let theme: AppTheme
    let label: LocalizedStringResource

    @State private var isCustom: Bool = false
    @Environment(\.locale) private var locale

    /// 系统等宽字体列表（首次访问缓存）。
    private static let systemMonospaceFonts: [String] = {
        (NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? [])
            .sorted()
    }()

    var body: some View {
        LabeledContent(String(localized: (label).withLocale(locale))) {
            HStack {
                Spacer(minLength: 0)
                if isCustom {
                    TextField(String(localized: (L10n.Settings.fontCustomPlaceholder).withLocale(locale)), text: Binding(
                        get: { settings.get("font-family") ?? "" },
                        set: { settings.set("font-family", $0.isEmpty ? nil : $0) }
                    ))
                    .themedTextField(theme)
                    .frame(minWidth: 200)

                    Button {
                        // 若当前 font-family 不在系统列表（之前自填的 Nerd Font 等），
                        // 回到 Picker 模式前把它清掉，避免 Picker 展示空白 selection。
                        let current = settings.get("font-family") ?? ""
                        if !current.isEmpty && !Self.systemMonospaceFonts.contains(current) {
                            settings.set("font-family", nil)
                        }
                        isCustom = false
                    } label: {
                        Text(L10n.Settings.fontListButton)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Picker("", selection: selectionBinding) {
                        Text(L10n.Settings.fontDefault).tag("")
                        ForEach(Self.systemMonospaceFonts, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        Text(L10n.Settings.fontCustom).tag("__custom__")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .onAppear {
            if let current = settings.get("font-family"),
               !Self.systemMonospaceFonts.contains(current) {
                isCustom = true
            }
        }
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { settings.get("font-family") ?? "" },
            set: { newValue in
                if newValue == "__custom__" {
                    isCustom = true
                } else if newValue.isEmpty {
                    settings.set("font-family", nil)
                } else {
                    settings.set("font-family", newValue)
                }
            }
        )
    }
}
