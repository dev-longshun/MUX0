import Foundation
import Observation

/// Global i18n store. Holds the user's language preference (system/zh/en),
/// persists it to UserDefaults, and publishes a monotonic `tick` that AppKit
/// bridges read in order to rebuild their NSView labels when language changes.
@Observable
final class LanguageStore {
    /// Language preference. `.system` defers to `Locale.current`.
    enum Preference: String, CaseIterable, Codable, Sendable {
        case system
        case zh
        case en
    }

    static let defaultStorageKey = "mux0.language"
    static let shared = LanguageStore(storageKey: defaultStorageKey, defaults: .standard)

    private let storageKey: String
    private let defaults: UserDefaults

    /// Monotonic counter for AppKit refresh triggers. Increments whenever
    /// `preference` changes. Overflow is intentional (&+=) — the absolute
    /// value doesn't matter, only "did it change".
    private(set) var tick: Int = 0

    var preference: Preference {
        didSet {
            guard preference != oldValue else { return }
            defaults.set(preference.rawValue, forKey: storageKey)
            tick &+= 1
        }
    }

    init(storageKey: String, defaults: UserDefaults) {
        self.storageKey = storageKey
        self.defaults = defaults
        if let raw = defaults.string(forKey: storageKey),
           let pref = Preference(rawValue: raw) {
            self.preference = pref
        } else {
            self.preference = .system
        }
    }

    /// The locale to inject into SwiftUI's `\.locale` environment.
    var locale: Locale {
        switch preference {
        case .system: return .current
        case .zh:     return Locale(identifier: "zh-Hans")
        case .en:     return Locale(identifier: "en")
        }
    }

    /// Bundle to hand to `Bundle.localizedString(forKey:value:table:)` for AppKit
    /// code paths that can't use SwiftUI's `\.locale` environment.
    /// Falls back to the parent bundle if the lproj directory can't be resolved.
    var effectiveBundle: Bundle {
        let parent = Bundle(for: LanguageStore.self)
        let code: String
        switch preference {
        case .system:
            code = Locale.current.language.languageCode?.identifier == "zh" ? "zh-Hans" : "en"
        case .zh: code = "zh-Hans"
        case .en: code = "en"
        }
        guard let path = parent.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return parent }
        return bundle
    }
}
