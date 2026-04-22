import XCTest
@testable import mux0

final class LanguageStoreTests: XCTestCase {
    private let testKey = "mux0.language.test"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testDefaultPreferenceIsSystem() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        XCTAssertEqual(store.preference, .system)
    }

    func testPreferencePersists() {
        let store1 = LanguageStore(storageKey: testKey, defaults: .standard)
        store1.preference = .zh
        let store2 = LanguageStore(storageKey: testKey, defaults: .standard)
        XCTAssertEqual(store2.preference, .zh)
    }

    func testInvalidStoredValueFallsBackToSystem() {
        UserDefaults.standard.set("bogus", forKey: testKey)
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        XCTAssertEqual(store.preference, .system)
    }

    func testTickIncrementsOnPreferenceChange() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        let before = store.tick
        store.preference = .zh
        XCTAssertEqual(store.tick, before &+ 1)
    }

    func testTickDoesNotIncrementOnSameValue() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        store.preference = .zh
        let mid = store.tick
        store.preference = .zh
        XCTAssertEqual(store.tick, mid)
    }

    func testLocaleForZh() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        store.preference = .zh
        XCTAssertEqual(store.locale.identifier, "zh-Hans")
    }

    func testLocaleForEn() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        store.preference = .en
        XCTAssertEqual(store.locale.identifier, "en")
    }

    func testLocaleForSystemMatchesCurrent() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        store.preference = .system
        XCTAssertEqual(store.locale, Locale.current)
    }

    func testEffectiveBundleForZhReturnsZhHansLproj() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        store.preference = .zh
        let value = store.effectiveBundle.localizedString(forKey: "sidebar.title", value: nil, table: nil)
        XCTAssertFalse(value.isEmpty)
        XCTAssertTrue(store.effectiveBundle.bundlePath.contains("zh-Hans.lproj"),
                      "bundlePath = \(store.effectiveBundle.bundlePath)")
    }

    func testEffectiveBundleForEnReturnsEnLproj() {
        let store = LanguageStore(storageKey: testKey, defaults: .standard)
        store.preference = .en
        XCTAssertTrue(store.effectiveBundle.bundlePath.contains("en.lproj"),
                      "bundlePath = \(store.effectiveBundle.bundlePath)")
    }
}
