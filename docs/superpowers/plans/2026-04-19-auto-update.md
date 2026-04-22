# Auto-Update (Sparkle) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship in-app auto-update via Sparkle wired to GitHub Releases. Sidebar footer shows `v{version}` + red dot when update available; clicking jumps to a new `Settings → Update` section with check/download/install/skip/dismiss/retry flow; releases are published via a tag-triggered GitHub Actions workflow that generates an EdDSA-signed `appcast.xml`.

**Architecture:** Sparkle (SPM dep, 2.6+) owned by a `SparkleBridge` singleton. A custom `UpdateUserDriver` implements `SPUUserDriver` to route every Sparkle event into an `@Observable UpdateStore`, which drives both the sidebar red dot and the settings `UpdateSectionView`. Debug builds stub out the bridge entirely via `#if !DEBUG`. Release pipeline: tag push → Actions runs xcodegen + xcodebuild + create-dmg + sign_update + appcast render, then `gh release create`.

**Tech Stack:** Swift 5 / SwiftUI / AppKit / Sparkle 2.6+ / XcodeGen / GitHub Actions / XCTest

**Spec reference:** `docs/superpowers/specs/2026-04-19-auto-update-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `project.yml` | Modify | Add Sparkle SPM dep, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `INFOPLIST_KEY_SU*` keys |
| `mux0/Update/UpdateState.swift` | Create | `enum UpdateState` with 7 cases (idle / checking / upToDate / updateAvailable / downloading / readyToInstall / error) |
| `mux0/Update/UpdateStore.swift` | Create | `@Observable` store; `state`, `currentVersion`, `hasUpdate` computed, mutation helpers |
| `mux0Tests/UpdateStoreTests.swift` | Create | Exhaustive state-transition coverage + `hasUpdate` derivation |
| `mux0/Update/SparkleBridge.swift` | Create | Singleton owning `SPUUpdater` (Release) / stub (Debug); user-facing API: `checkForUpdates`, `downloadAndInstall`, `installNow`, `skipVersion`, `dismiss`, `retry` |
| `mux0/Update/UpdateUserDriver.swift` | Create | Implements `SPUUserDriver` protocol; maps Sparkle callbacks → `UpdateStore` mutations (MainActor) |
| `mux0/Settings/SettingsSection.swift` | Modify | Add `case update` with label `"Update"` |
| `mux0/Settings/Sections/UpdateSectionView.swift` | Create | SwiftUI view rendering the 7 UI states |
| `mux0/Settings/SettingsView.swift` | Modify | Add `initialSection` init param + observe mid-session section changes; wire `.update` branch in `sectionBody` |
| `mux0/ContentView.swift` | Modify | Instantiate `UpdateStore`, inject via `.environment`, thread `userInfo["section"]` through to `SettingsView`, kick off 3 s launch check, wire `SparkleBridge.shared.store` + `start()` |
| `mux0/Sidebar/SidebarView.swift` | Modify | Redesign footer: version text (left, clickable) + pulsing dot + Spacer + gear (right) |
| `.github/workflows/release.yml` | Create | Tag-triggered build + sign + publish workflow |
| `.github/scripts/render-appcast.sh` | Create | Helper script: read version/signature/changelog, emit `appcast.xml` |
| `CLAUDE.md` | Modify | Directory Structure tree (add `Update/`), Common Tasks row, commit scopes list |
| `AGENTS.md` | Modify | Mirror `CLAUDE.md` changes |
| `docs/architecture.md` | Modify | New `## Auto-Update` section with data-flow diagram |
| `docs/settings-reference.md` | Modify | Document Update section UI and the Sparkle-managed `UserDefaults` keys |
| `docs/testing.md` | Modify | Add manual QA procedure for the update flow |
| `docs/build.md` | Modify | Add Release subsection: key bootstrap, tag-push workflow, appcast format |

---

## Pre-Flight Checklist (one-time human setup — NOT automated here)

These are documented in the plan but executed by a human, not this plan's tasks:

1. Run Sparkle's `generate_keys` locally once. Public key → `project.yml` placeholder. Private key → GitHub repo secret `SPARKLE_ED_PRIVATE_KEY`.
2. Create a GitHub repo secret `SPARKLE_ED_PRIVATE_KEY` with the exported private key.
3. Verify `gh auth login` works and has push access to `10xChengTu/mux0`.

Execution of the plan's code tasks does **not** depend on these being done. Only the first tag push + release will.

---

## Task 1: Add Sparkle SPM dep + version metadata to project.yml

**Files:**
- Modify: `project.yml`

- [ ] **Step 1.1: Read current project.yml to understand the diff scope**

```bash
cat project.yml
```

- [ ] **Step 1.2: Add `packages` block + Sparkle dep + Info.plist keys**

Open `project.yml` and make the following changes:

Add at the top level, **after** the `options:` block and **before** `targets:`:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
```

In `targets.mux0.dependencies`, append a new entry (keeping existing ones):

```yaml
    dependencies:
      - sdk: Metal.framework
      - sdk: QuartzCore.framework
      - sdk: AppKit.framework
      - package: Sparkle
        product: Sparkle
```

In `targets.mux0.settings.base`, add these keys (alongside the existing ones, do not remove):

```yaml
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        INFOPLIST_KEY_SUFeedURL: "https://github.com/10xChengTu/mux0/releases/latest/download/appcast.xml"
        INFOPLIST_KEY_SUPublicEDKey: "REPLACE_WITH_SPARKLE_ED_PUBKEY"
        INFOPLIST_KEY_SUEnableAutomaticChecks: "YES"
        INFOPLIST_KEY_SUScheduledCheckInterval: "86400"
```

- [ ] **Step 1.3: Regenerate the Xcode project**

```bash
xcodegen generate
```

Expected: `Created project at /Users/.../mux0.xcodeproj`. No errors. `Package.resolved` will be populated on the next build.

- [ ] **Step 1.4: Verify the project builds with the new dependency**

```bash
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`. First invocation will fetch Sparkle via SPM (takes ~30 s). If this fails due to a missing `libghostty.a`, run `./scripts/build-vendor.sh` first.

- [ ] **Step 1.5: Verify tests still pass**

```bash
xcodebuild test -project mux0.xcodeproj -scheme mux0Tests 2>&1 | tail -20
```

Expected: all existing tests pass (no code changed yet, only build config).

- [ ] **Step 1.6: Commit**

```bash
git add project.yml mux0.xcodeproj
git commit -m "$(cat <<'EOF'
build(update): add Sparkle SPM dep and version/appcast Info.plist keys

- packages: Sparkle from 2.6.0
- MARKETING_VERSION 0.1.0 / CURRENT_PROJECT_VERSION 1
- Info.plist keys: SUFeedURL, SUPublicEDKey (placeholder),
  SUEnableAutomaticChecks, SUScheduledCheckInterval (86400)

Public EdDSA key will be filled during First Release Bootstrap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `UpdateState` enum

**Files:**
- Create: `mux0/Update/UpdateState.swift`

- [ ] **Step 2.1: Create the directory and file**

```bash
mkdir -p mux0/Update
```

Write `mux0/Update/UpdateState.swift`:

```swift
import Foundation

/// Drives the entire UpdateSectionView UI and the sidebar red-dot visibility.
/// Single source of truth for the user-visible auto-update flow.
enum UpdateState: Equatable {
    /// Default. Shows current version + "Check for Updates" button.
    case idle

    /// Network request in flight.
    case checking

    /// Confirmed no update. Auto-transitions back to `.idle` after 3 s.
    case upToDate

    /// Update found and ready to download.
    /// - version: e.g. "0.2.0"
    /// - releaseNotes: plain text body from appcast `<description>` CDATA; may be nil.
    case updateAvailable(version: String, releaseNotes: String?)

    /// Download in progress.
    /// - progress: 0.0 ... 1.0
    case downloading(progress: Double)

    /// Transient (milliseconds) between download-complete and app relaunch.
    case readyToInstall

    /// Any failure. Shows red card + Retry.
    case error(String)
}
```

- [ ] **Step 2.2: Verify it compiles**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. (Note: `xcodegen generate` picks up the new file on disk.)

- [ ] **Step 2.3: Commit**

```bash
git add mux0/Update/UpdateState.swift mux0.xcodeproj
git commit -m "$(cat <<'EOF'
feat(update): add UpdateState enum with 7 cases

Single source of truth for the auto-update UI flow: idle, checking,
upToDate, updateAvailable, downloading, readyToInstall, error.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `UpdateStore` (+ unit tests)

**Files:**
- Create: `mux0/Update/UpdateStore.swift`
- Create: `mux0Tests/UpdateStoreTests.swift`

- [ ] **Step 3.1: Write the failing test file**

Write `mux0Tests/UpdateStoreTests.swift`:

```swift
import XCTest
@testable import mux0

final class UpdateStoreTests: XCTestCase {

    func testDefaultStateIsIdle() {
        let s = UpdateStore(currentVersion: "0.1.0")
        XCTAssertEqual(s.state, .idle)
    }

    func testCurrentVersionIsStoredVerbatim() {
        let s = UpdateStore(currentVersion: "1.2.3")
        XCTAssertEqual(s.currentVersion, "1.2.3")
    }

    func testHasUpdateFalseWhenIdle() {
        let s = UpdateStore(currentVersion: "0.1.0")
        XCTAssertFalse(s.hasUpdate)
    }

    func testHasUpdateTrueWhenUpdateAvailable() {
        let s = UpdateStore(currentVersion: "0.1.0")
        s.setUpdateAvailable(version: "0.2.0", releaseNotes: "fix bug")
        XCTAssertTrue(s.hasUpdate)
        XCTAssertEqual(s.state, .updateAvailable(version: "0.2.0", releaseNotes: "fix bug"))
    }

    func testHasUpdateTrueWhileDownloading() {
        let s = UpdateStore(currentVersion: "0.1.0")
        s.setUpdateAvailable(version: "0.2.0", releaseNotes: nil)
        s.setDownloading(progress: 0.3)
        XCTAssertTrue(s.hasUpdate)
        XCTAssertEqual(s.state, .downloading(progress: 0.3))
    }

    func testHasUpdateFalseAfterUpToDate() {
        let s = UpdateStore(currentVersion: "0.1.0")
        s.setChecking()
        s.setUpToDate()
        XCTAssertFalse(s.hasUpdate)
        XCTAssertEqual(s.state, .upToDate)
    }

    func testErrorState() {
        let s = UpdateStore(currentVersion: "0.1.0")
        s.setError("Network error")
        XCTAssertEqual(s.state, .error("Network error"))
        XCTAssertFalse(s.hasUpdate)
    }

    func testResetToIdle() {
        let s = UpdateStore(currentVersion: "0.1.0")
        s.setUpdateAvailable(version: "0.2.0", releaseNotes: nil)
        s.resetToIdle()
        XCTAssertEqual(s.state, .idle)
    }

    func testProgressMonotonicAccepted() {
        let s = UpdateStore(currentVersion: "0.1.0")
        s.setDownloading(progress: 0.1)
        s.setDownloading(progress: 0.5)
        s.setDownloading(progress: 1.0)
        XCTAssertEqual(s.state, .downloading(progress: 1.0))
    }
}
```

- [ ] **Step 3.2: Run the tests — expected to fail (no UpdateStore yet)**

```bash
xcodebuild test -project mux0.xcodeproj -scheme mux0Tests -only-testing:mux0Tests/UpdateStoreTests 2>&1 | tail -15
```

Expected: build error `cannot find 'UpdateStore' in scope`.

- [ ] **Step 3.3: Write `UpdateStore.swift`**

Write `mux0/Update/UpdateStore.swift`:

```swift
import Foundation
import Observation

/// Single source of truth for the auto-update flow. Lives in the SwiftUI
/// environment; read by SidebarView (red-dot visibility) and
/// UpdateSectionView (main UI). All mutations happen here — the Sparkle
/// UserDriver calls these helpers; views never mutate state directly.
@Observable
final class UpdateStore {
    /// Current app version (MARKETING_VERSION). Read once at init.
    let currentVersion: String

    /// Current UI state.
    var state: UpdateState = .idle

    /// Whether the sidebar should show the red pulsing dot.
    /// True for `.updateAvailable` and `.downloading` only. The download
    /// phase still counts as "an update exists" — if the user cancelled,
    /// the flow would go back to `.updateAvailable` or `.error`.
    var hasUpdate: Bool {
        switch state {
        case .updateAvailable, .downloading, .readyToInstall:
            return true
        default:
            return false
        }
    }

    init(currentVersion: String) {
        self.currentVersion = currentVersion
    }

    func setChecking() { state = .checking }

    func setUpToDate() { state = .upToDate }

    func setUpdateAvailable(version: String, releaseNotes: String?) {
        state = .updateAvailable(version: version, releaseNotes: releaseNotes)
    }

    func setDownloading(progress: Double) {
        state = .downloading(progress: progress)
    }

    func setReadyToInstall() { state = .readyToInstall }

    func setError(_ message: String) { state = .error(message) }

    func resetToIdle() { state = .idle }
}
```

- [ ] **Step 3.4: Run the tests — expected PASS**

```bash
xcodegen generate && xcodebuild test -project mux0.xcodeproj -scheme mux0Tests -only-testing:mux0Tests/UpdateStoreTests 2>&1 | tail -20
```

Expected: all 9 tests pass.

- [ ] **Step 3.5: Commit**

```bash
git add mux0/Update/UpdateStore.swift mux0Tests/UpdateStoreTests.swift mux0.xcodeproj
git commit -m "$(cat <<'EOF'
feat(update): add UpdateStore (@Observable) + unit tests

Single source of truth for the auto-update flow. hasUpdate returns
true for updateAvailable/downloading/readyToInstall, driving the
sidebar red-dot visibility.

9 unit tests cover state transitions + hasUpdate derivation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `SparkleBridge` (Debug no-op / Release active)

**Files:**
- Create: `mux0/Update/SparkleBridge.swift`

- [ ] **Step 4.1: Write `SparkleBridge.swift`**

Write `mux0/Update/SparkleBridge.swift`:

```swift
import Foundation
#if !DEBUG
import Sparkle
#endif

/// Wraps SPUUpdater + our custom SPUUserDriver. The only file (along with
/// UpdateUserDriver) that imports Sparkle — keeps the dependency surface
/// contained, matching how GhosttyBridge isolates libghostty.
///
/// Debug builds compile this class as a no-op stub:
///   - `isActive` returns false
///   - all action methods log and return
/// This avoids hitting the real appcast URL during development and keeps
/// the IDE green without a valid SUPublicEDKey.
final class SparkleBridge {
    static let shared = SparkleBridge()

    /// Injected by mux0App once the UpdateStore is created. The driver
    /// mutates store state; the bridge forwards user actions here so the
    /// driver can reach the store for consistency-check paths.
    weak var store: UpdateStore?

    var isActive: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    // MARK: - Public API (UI calls these)

    func start() {
        #if !DEBUG
        startUpdater()
        #endif
    }

    func checkForUpdates(silently: Bool) {
        #if DEBUG
        print("[SparkleBridge] DEBUG stub: checkForUpdates(silently: \(silently))")
        #else
        if silently {
            updater?.checkForUpdatesInBackground()
        } else {
            updater?.checkForUpdates()
        }
        #endif
    }

    func downloadAndInstall() {
        #if DEBUG
        print("[SparkleBridge] DEBUG stub: downloadAndInstall()")
        #else
        driver?.userRequestedDownloadAndInstall()
        #endif
    }

    func installNow() {
        #if DEBUG
        print("[SparkleBridge] DEBUG stub: installNow()")
        #else
        driver?.userRequestedInstallNow()
        #endif
    }

    func skipVersion() {
        #if DEBUG
        print("[SparkleBridge] DEBUG stub: skipVersion()")
        #else
        driver?.userRequestedSkipVersion()
        #endif
    }

    func dismiss() {
        #if DEBUG
        print("[SparkleBridge] DEBUG stub: dismiss()")
        #else
        driver?.userRequestedDismiss()
        store?.resetToIdle()
        #endif
    }

    func retry() {
        #if DEBUG
        print("[SparkleBridge] DEBUG stub: retry()")
        #else
        store?.resetToIdle()
        checkForUpdates(silently: false)
        #endif
    }

    // MARK: - Release-only internals

    #if !DEBUG
    private var updater: SPUUpdater?
    private var driver: UpdateUserDriver?

    private func startUpdater() {
        guard let store = store else {
            print("[SparkleBridge] ERROR: startUpdater called before store injected")
            return
        }
        let driver = UpdateUserDriver(store: store, bridge: self)
        let updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: nil
        )
        do {
            try updater.start()
        } catch {
            store.setError("Updater failed to start: \(error.localizedDescription)")
            return
        }
        self.updater = updater
        self.driver = driver
    }
    #endif
}
```

- [ ] **Step 4.2: Add a one-liner unit test asserting the Debug stub**

Append to `mux0Tests/UpdateStoreTests.swift` (or create `mux0Tests/SparkleBridgeTests.swift` if you prefer a dedicated file) a single test case:

```swift
    func testSparkleBridgeIsInactiveInDebug() {
        // Tests always run in Debug configuration; isActive must be false
        // to guarantee no live-network update checks during testing.
        XCTAssertFalse(SparkleBridge.shared.isActive)
    }
```

Run it:

```bash
xcodebuild test -project mux0.xcodeproj -scheme mux0Tests -only-testing:mux0Tests/UpdateStoreTests/testSparkleBridgeIsInactiveInDebug 2>&1 | tail -10
```

Expected: PASS. If it fails, the `#if DEBUG` guard in `SparkleBridge.isActive` is wrong.

- [ ] **Step 4.3: Verify it compiles (Debug)**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. Debug builds don't reference `Sparkle` or `UpdateUserDriver` at all — the `#if !DEBUG` guards everything.

- [ ] **Step 4.4: Verify it compiles (Release)**

```bash
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Release build 2>&1 | tail -15
```

Expected: fails with `cannot find 'UpdateUserDriver' in scope` — the driver doesn't exist yet. This is EXPECTED; Task 5 adds it. Commit Task 4 regardless since Debug builds are fine.

- [ ] **Step 4.5: Commit**

```bash
git add mux0/Update/SparkleBridge.swift mux0.xcodeproj
git commit -m "$(cat <<'EOF'
feat(update): add SparkleBridge singleton (Debug stub / Release active)

Wraps SPUUpdater. Debug builds compile the class as a no-op — isActive
returns false, all methods log and return. Only file (along with the
upcoming UpdateUserDriver) that imports Sparkle.

Release build incomplete until UpdateUserDriver lands (next task).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `UpdateUserDriver` (SPUUserDriver → UpdateStore mutations)

**Files:**
- Create: `mux0/Update/UpdateUserDriver.swift`

- [ ] **Step 5.1: Write `UpdateUserDriver.swift`**

Write `mux0/Update/UpdateUserDriver.swift`:

```swift
#if !DEBUG
import Foundation
import Sparkle

/// Implements Sparkle's SPUUserDriver protocol, the interface through which
/// Sparkle notifies the app of update-lifecycle events and receives user
/// decisions. Every callback mutates UpdateStore on the main actor so the
/// SwiftUI views observe the change; every user action (downloadAndInstall,
/// skip, dismiss, retry) is routed here via SparkleBridge, which stores the
/// pending reply blocks and calls them when the user clicks.
///
/// Lifecycle (happy path):
///   showUpdateInFocus → showUpdateFound(...) → (user click Download & Install)
///   → showDownloadInitiated → showDownloadDidReceiveData(progress) x N
///   → showDownloadDidFinishLoading → showReady(toInstallAndRelaunch)
///   → Sparkle quits + relaunches.
///
/// Compiled only in Release (`#if !DEBUG`) — Debug has no Sparkle in scope.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {

    private weak var store: UpdateStore?
    private weak var bridge: SparkleBridge?

    // Reply blocks Sparkle hands us; we stash them, then invoke when the
    // user acts from our custom UI.
    private var pendingUpdateReply: ((SPUUserUpdateChoice) -> Void)?
    private var pendingInstallReply: ((SPUUserUpdateChoice) -> Void)?
    private var latestAppcastItem: SUAppcastItem?

    init(store: UpdateStore, bridge: SparkleBridge) {
        self.store = store
        self.bridge = bridge
        super.init()
    }

    // MARK: - Public (called by SparkleBridge when user clicks)

    func userRequestedDownloadAndInstall() {
        pendingUpdateReply?(.install)
        pendingUpdateReply = nil
    }

    func userRequestedInstallNow() {
        pendingInstallReply?(.install)
        pendingInstallReply = nil
    }

    func userRequestedSkipVersion() {
        pendingUpdateReply?(.skip)
        pendingUpdateReply = nil
        store?.resetToIdle()
    }

    func userRequestedDismiss() {
        pendingUpdateReply?(.dismiss)
        pendingUpdateReply = nil
    }

    // MARK: - SPUUserDriver

    nonisolated func showCanCheck(forUpdates canCheckForUpdates: Bool) {
        // No-op: our UI decides button enablement from `store.state`.
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        store?.setChecking()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        self.latestAppcastItem = appcastItem
        self.pendingUpdateReply = reply
        store?.setUpdateAvailable(
            version: appcastItem.displayVersionString ?? appcastItem.versionString,
            releaseNotes: appcastItem.itemDescription
        )
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Not used: we render notes from appcastItem.itemDescription at the
        // moment of showUpdateFound(...). If a release ships notes as a
        // separate HTML asset via sparkle:releaseNotesLink, Sparkle would
        // call this; we'd optionally plumb it into UpdateStore later.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // Non-fatal — we already have the inline release notes.
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        store?.setUpToDate()
        acknowledgement()
        // Auto-transition back to idle after 3 s.
        Task { @MainActor [weak store] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if case .upToDate = store?.state {
                store?.resetToIdle()
            }
        }
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        store?.setError(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        store?.setDownloading(progress: 0)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        // Sparkle passes this once upfront; we don't display bytes, only percent,
        // so we can ignore and compute from the running total when chunks arrive.
    }

    private var expectedTotalBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        // If Sparkle never called the expectedContentLength path, fall back
        // to indeterminate 0% — avoids divide-by-zero.
        let total = expectedTotalBytes > 0 ? expectedTotalBytes : max(receivedBytes, 1)
        let progress = min(1.0, Double(receivedBytes) / Double(total))
        store?.setDownloading(progress: progress)
    }

    func showDownloadDidStartExtractingUpdate() {
        store?.setDownloading(progress: 1.0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        store?.setDownloading(progress: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        store?.setReadyToInstall()
        // Auto-install: match input0 behaviour.
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        // Sparkle is about to quit + install. UI unchanged from readyToInstall.
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        // Only called if Sparkle ran the installer in-process without quitting
        // (uncommon for .dmg installs). Acknowledge and reset.
        store?.resetToIdle()
        acknowledgement()
    }

    func showUpdateInFocus() {
        // Reserved for bringing focus to the update UI; our settings panel
        // is reached by the user clicking the sidebar version number, so
        // no-op here.
    }

    func dismissUpdateInstallation() {
        // Sparkle telling us the install flow ended (success or user cancel).
    }
}
#endif
```

- [ ] **Step 5.2: Verify Release build now succeeds**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Release build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. If Sparkle's SPUUserDriver protocol surface has changed between 2.6 and the fetched version, some method signatures may need tweaking — fix locally by reading the Sparkle headers from `DerivedData/SourcePackages/checkouts/Sparkle/...`.

- [ ] **Step 5.3: Verify Debug still builds**

```bash
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. The entire file is guarded by `#if !DEBUG` so it's simply absent from Debug.

- [ ] **Step 5.4: Commit**

```bash
git add mux0/Update/UpdateUserDriver.swift mux0.xcodeproj
git commit -m "$(cat <<'EOF'
feat(update): add UpdateUserDriver (SPUUserDriver → UpdateStore)

Maps Sparkle lifecycle callbacks (showUserInitiatedUpdateCheck,
showUpdateFound, showDownloadDidReceiveData, showReady toInstall
AndRelaunch, showUpdaterError) to UpdateStore mutations on MainActor.
Auto-installs on download complete to match input0 behaviour.

Release-only (#if !DEBUG).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add `.update` case to `SettingsSection`

**Files:**
- Modify: `mux0/Settings/SettingsSection.swift`

- [ ] **Step 6.1: Extend the enum**

Replace the entirety of `mux0/Settings/SettingsSection.swift`:

```swift
import Foundation

/// 设置视图的五个硬编码分类。顺序即 tab 条显示顺序，不可重排。
enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case font
    case terminal
    case shell
    case update

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appearance: return "Appearance"
        case .font:       return "Font"
        case .terminal:   return "Terminal"
        case .shell:      return "Shell"
        case .update:     return "Update"
        }
    }
}
```

- [ ] **Step 6.2: Verify it still compiles (will warn until `SettingsView` handles the new case)**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -15
```

Expected: either BUILD SUCCEEDED with a switch-exhaustiveness warning, or BUILD FAILED with `Switch must be exhaustive`. Either way, continue — Task 7/8 add the missing branches.

- [ ] **Step 6.3: Commit**

```bash
git add mux0/Settings/SettingsSection.swift
git commit -m "$(cat <<'EOF'
feat(settings): add .update case to SettingsSection enum

Fifth section in the tab bar order, label "Update".

Switch-exhaustiveness compile warnings in SettingsView.sectionBody
are resolved by Task 7/8 which add the view branch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Create `UpdateSectionView`

**Files:**
- Create: `mux0/Settings/Sections/UpdateSectionView.swift`

- [ ] **Step 7.1: Write the view**

Write `mux0/Settings/Sections/UpdateSectionView.swift`:

```swift
import SwiftUI

struct UpdateSectionView: View {
    let theme: AppTheme
    let updateStore: UpdateStore

    @Environment(ThemeManager.self) private var themeManager

    private var isDebug: Bool {
        !SparkleBridge.shared.isActive
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Space.md) {
                headerRow
                contentForState
                if isDebug {
                    debugHint
                }
                Spacer(minLength: 0)
            }
            .padding(DT.Space.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sections

    private var headerRow: some View {
        HStack(spacing: DT.Space.sm) {
            Text("Current version:")
                .font(Font(DT.Font.body))
                .foregroundColor(Color(theme.textSecondary))
            Text("v\(updateStore.currentVersion)")
                .font(Font(DT.Font.body))
                .foregroundColor(Color(theme.textPrimary))
            Spacer()
        }
    }

    @ViewBuilder
    private var contentForState: some View {
        switch updateStore.state {
        case .idle:
            idleView
        case .checking:
            checkingView
        case .upToDate:
            upToDateView
        case .updateAvailable(let version, let notes):
            updateAvailableView(version: version, notes: notes)
        case .downloading(let progress):
            downloadingView(progress: progress)
        case .readyToInstall:
            readyToInstallView
        case .error(let message):
            errorView(message: message)
        }
    }

    private var idleView: some View {
        Button {
            SparkleBridge.shared.checkForUpdates(silently: false)
        } label: {
            Text("Check for Updates")
                .font(Font(DT.Font.body))
        }
        .disabled(isDebug)
    }

    private var checkingView: some View {
        HStack(spacing: DT.Space.sm) {
            ProgressView().controlSize(.small)
            Text("Checking…")
                .foregroundColor(Color(theme.textSecondary))
        }
    }

    private var upToDateView: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(theme.success))
            Text("You're on the latest version.")
                .foregroundColor(Color(theme.textPrimary))
        }
    }

    private func updateAvailableView(version: String, notes: String?) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text("Version \(version) is available")
                .font(Font(DT.Font.body).bold())
                .foregroundColor(Color(theme.textPrimary))

            if let notes = notes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(Font(DT.Font.small))
                        .foregroundColor(Color(theme.textSecondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DT.Space.sm)
                }
                .frame(maxHeight: 128)
                .background(Color(theme.canvas).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
            }

            HStack(spacing: DT.Space.sm) {
                Button("Download & Install") {
                    SparkleBridge.shared.downloadAndInstall()
                }
                .buttonStyle(.borderedProminent)

                Button("Skip This Version") {
                    SparkleBridge.shared.skipVersion()
                }

                Spacer()

                Button {
                    SparkleBridge.shared.dismiss()
                } label: {
                    Text("Dismiss")
                        .font(Font(DT.Font.small))
                        .foregroundColor(Color(theme.textTertiary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DT.Space.md)
        .background(Color(theme.accentMuted))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .stroke(Color(theme.accent), lineWidth: DT.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            Text("Downloading… \(Int(progress * 100))%")
                .foregroundColor(Color(theme.textPrimary))
            ProgressView(value: progress)
                .tint(Color(theme.accent))
        }
    }

    private var readyToInstallView: some View {
        HStack(spacing: DT.Space.sm) {
            ProgressView().controlSize(.small)
            Text("Installing & relaunching…")
                .foregroundColor(Color(theme.textPrimary))
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(theme.danger))
                Text(message)
                    .font(Font(DT.Font.small))
                    .foregroundColor(Color(theme.textPrimary))
                Spacer()
            }
            Button("Retry") {
                SparkleBridge.shared.retry()
            }
        }
        .padding(DT.Space.md)
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                .stroke(Color(theme.danger), lineWidth: DT.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
    }

    private var debugHint: some View {
        Text("(Auto-update is disabled in Debug builds.)")
            .font(Font(DT.Font.small))
            .foregroundColor(Color(theme.textTertiary))
    }
}
```

- [ ] **Step 7.2: Verify the file compiles (still won't link until Task 8 wires it in)**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -15
```

Expected: BUILD FAILED with `Switch must be exhaustive` in `SettingsView.sectionBody` (because it doesn't yet have a `.update` branch). **This is expected** — Task 8 adds the branch. If any other error surfaces (e.g. a token mismatch like `DT.Stroke.hairline` not existing), fix inline by grepping the actual token names in `mux0/Theme/DesignTokens.swift`.

- [ ] **Step 7.3: Commit**

```bash
git add mux0/Settings/Sections/UpdateSectionView.swift mux0.xcodeproj
git commit -m "$(cat <<'EOF'
feat(settings): add UpdateSectionView rendering the 7 UI states

SwiftUI view for the new Settings → Update section. Reads UpdateStore,
dispatches user actions to SparkleBridge. In Debug builds, "Check for
Updates" is disabled and a hint line explains why.

Switch-exhaustiveness error in SettingsView.sectionBody is resolved
by the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Plumb `initialSection` + `.update` branch into `SettingsView`

**Files:**
- Modify: `mux0/Settings/SettingsView.swift`

- [ ] **Step 8.1: Read the current file and replace it**

Replace the entirety of `mux0/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    let theme: AppTheme
    let settings: SettingsConfigStore
    let updateStore: UpdateStore
    let onClose: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @State private var section: SettingsSection

    init(
        theme: AppTheme,
        settings: SettingsConfigStore,
        updateStore: UpdateStore,
        initialSection: SettingsSection? = nil,
        onClose: @escaping () -> Void
    ) {
        self.theme = theme
        self.settings = settings
        self.updateStore = updateStore
        self.onClose = onClose
        _section = State(initialValue: initialSection ?? .appearance)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBarView(
                theme: theme,
                selection: $section,
                onClose: onClose
            )
            .padding(.top, DT.Space.xs)
            .padding(.horizontal, DT.Space.xs)
            .padding(.bottom, DT.Space.xs)

            VStack(spacing: 0) {
                sectionBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .clipShape(RoundedRectangle(cornerRadius: TabBarView.stripRadius, style: .continuous))
            .padding(.horizontal, DT.Space.xs)
            .padding(.bottom, DT.Space.xs)
        }
        .background(Color(theme.canvas).opacity(themeManager.contentEffectiveOpacity))
        .tint(Color(theme.accent))
        // 允许 sidebar 的版本号点击在 Settings 已经打开时再次跳转到 Update section。
        .onReceive(NotificationCenter.default.publisher(for: .mux0OpenSettings)) { note in
            if let raw = note.userInfo?["section"] as? String,
               let next = SettingsSection(rawValue: raw) {
                section = next
            }
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch section {
        case .appearance: AppearanceSectionView(theme: theme, settings: settings)
        case .font:       FontSectionView(theme: theme, settings: settings)
        case .terminal:   TerminalSectionView(theme: theme, settings: settings)
        case .shell:      ShellSectionView(theme: theme, settings: settings)
        case .update:     UpdateSectionView(theme: theme, updateStore: updateStore)
        }
    }

    private var footer: some View {
        HStack {
            TextLinkButton(theme: theme, title: "Edit Config File…") {
                settings.openInEditor()
            }
            Spacer()
            Text("Changes apply live.")
                .font(Font(DT.Font.small))
                .foregroundColor(Color(theme.textTertiary))
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
        .background(Color(theme.canvas).opacity(themeManager.contentEffectiveOpacity))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(theme.border).opacity(0.5 * themeManager.contentEffectiveOpacity))
                .frame(height: DT.Stroke.hairline)
        }
    }
}
```

- [ ] **Step 8.2: Build — expected failure from `ContentView.swift`**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -15
```

Expected: BUILD FAILED in `ContentView.swift` at the `SettingsView(...)` call site — missing `updateStore:` arg. **Expected.** Task 9 fixes it.

- [ ] **Step 8.3: Commit**

```bash
git add mux0/Settings/SettingsView.swift
git commit -m "$(cat <<'EOF'
feat(settings): thread initialSection + updateStore into SettingsView

- New initialSection init param seeds @State private var section via
  _section = State(initialValue: ...). Defaults to .appearance when nil.
- Observe .mux0OpenSettings mid-session: if userInfo["section"] is set
  and maps to a valid SettingsSection rawValue, snap to it. Lets the
  sidebar version number re-jump to Update even if Settings is open.
- sectionBody gains the .update branch rendering UpdateSectionView.

ContentView call site needs updating (next task).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Wire `UpdateStore` into `ContentView` + thread `userInfo["section"]`

**Files:**
- Modify: `mux0/ContentView.swift`

- [ ] **Step 9.1: Add UpdateStore state + section routing + launch check**

In `mux0/ContentView.swift`:

1. Add a new `@State` property alongside the existing stores:

```swift
    @State private var updateStore = UpdateStore(
        currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    )
    @State private var pendingSettingsSection: SettingsSection?
```

2. Pass `updateStore` to `SidebarView` (Task 10 will use it):

```swift
                if !sidebarCollapsed {
                    SidebarView(
                        store: store,
                        statusStore: statusStore,
                        pwdStore: pwdStore,
                        theme: themeManager.theme,
                        backgroundOpacity: bgOpacity,
                        showStatusIndicators: showStatusIndicators,
                        updateStore: updateStore
                    )
```

3. Update the `SettingsView(...)` call site (inside the `if showSettings { ... }` block):

```swift
                    if showSettings {
                        SettingsView(
                            theme: themeManager.theme,
                            settings: settingsStore,
                            updateStore: updateStore,
                            initialSection: pendingSettingsSection,
                            onClose: { showSettings = false }
                        )
                    }
```

4. Replace the `.onReceive(NotificationCenter.default.publisher(for: .mux0OpenSettings))` closure with:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .mux0OpenSettings)) { note in
            if let raw = note.userInfo?["section"] as? String,
               let section = SettingsSection(rawValue: raw) {
                pendingSettingsSection = section
            } else {
                pendingSettingsSection = nil
            }
            showSettings = true
        }
```

5. In the existing `.onAppear { ... }` closure, add at the end (after the hook listener block):

```swift
            // Auto-update: wire SparkleBridge and schedule the silent launch check.
            SparkleBridge.shared.store = updateStore
            SparkleBridge.shared.start()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                SparkleBridge.shared.checkForUpdates(silently: true)
            }
```

- [ ] **Step 9.2: Build — expected failure from SidebarView (Task 10)**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -15
```

Expected: BUILD FAILED in `SidebarView.swift` at the call site (no `updateStore` init arg). **Expected.** Task 10 fixes it.

- [ ] **Step 9.3: Commit**

```bash
git add mux0/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(update): wire UpdateStore into ContentView + section routing

- Instantiate UpdateStore from Bundle's CFBundleShortVersionString.
- Thread userInfo["section"] from .mux0OpenSettings into a
  pendingSettingsSection @State; consumed by SettingsView init.
- On appear: inject store into SparkleBridge.shared, call start()
  (no-op in Debug), and schedule a 3 s silent launch check.

SidebarView needs the updateStore param next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Redesign Sidebar footer (version + dot + gear)

**Files:**
- Modify: `mux0/Sidebar/SidebarView.swift`

- [ ] **Step 10.1: Add `updateStore` parameter and redesign footer**

In `mux0/Sidebar/SidebarView.swift`:

1. Add to the `SidebarView` struct properties (after `backgroundOpacity`):

```swift
    /// Drives the footer version number + red pulsing dot when an update
    /// is available. Clicking the version jumps to Settings → Update.
    @Bindable var updateStore: UpdateStore
```

2. Replace the `private var footer: some View { ... }` block entirely with:

```swift
    private var footer: some View {
        HStack(spacing: DT.Space.xs) {
            versionButton
            if updateStore.hasUpdate {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(Color(theme.danger))
                    .symbolEffect(.pulse)
                    .help("Update available")
            }
            Spacer()
            IconButton(theme: theme, help: "Settings") {
                NotificationCenter.default.post(name: .mux0OpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(theme.textSecondary))
            }
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, DT.Space.sm)
    }

    private var versionButton: some View {
        Button {
            NotificationCenter.default.post(
                name: .mux0OpenSettings,
                object: nil,
                userInfo: ["section": "update"]
            )
        } label: {
            Text("v\(updateStore.currentVersion)")
                .font(Font(DT.Font.small))
                .foregroundColor(Color(theme.textSecondary))
        }
        .buttonStyle(.plain)
        .help("Check for updates")
    }
```

- [ ] **Step 10.2: Build — expected PASS**

```bash
xcodegen generate && xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. The full app now compiles with the new footer.

- [ ] **Step 10.3: Manual smoke — run the app and eyeball the footer**

```bash
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug -derivedDataPath /tmp/mux0-debug build 2>&1 | tail -5
open /tmp/mux0-debug/Build/Products/Debug/mux0.app
```

Expected: app launches. Sidebar footer shows `v0.1.0` on the left, gear on the right, nothing between (no dot — Debug build never detects updates). Clicking `v0.1.0` opens Settings scrolled to the Update section showing `Current version: v0.1.0` + `(Auto-update is disabled in Debug builds.)` hint.

- [ ] **Step 10.4: Run tests to confirm nothing regressed**

```bash
xcodebuild test -project mux0.xcodeproj -scheme mux0Tests 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 10.5: Commit**

```bash
git add mux0/Sidebar/SidebarView.swift
git commit -m "$(cat <<'EOF'
feat(sidebar): redesign footer with version + pulsing dot + gear

Layout: v{version} [• red dot if hasUpdate] [spacer] [gear].
Clicking the version text posts .mux0OpenSettings with userInfo
["section": "update"] so ContentView opens Settings scrolled to the
Update pane. Dot uses SF Symbol circle.fill with .symbolEffect(.pulse).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Documentation updates

**Files:**
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`
- Modify: `docs/architecture.md`
- Modify: `docs/settings-reference.md`
- Modify: `docs/testing.md`
- Modify: `docs/build.md`

- [ ] **Step 11.1: Update `CLAUDE.md` — Directory Structure + Common Tasks**

In `CLAUDE.md`, inside the Directory Structure code block, insert after the `Sidebar/` block:

```
├── Update/
│   ├── UpdateState.swift         — 自动更新 UI 状态枚举（idle / checking / upToDate / updateAvailable / downloading / readyToInstall / error）
│   ├── UpdateStore.swift         — @Observable，自动更新状态存储（sidebar 红点 + Settings Update section 都读这个）
│   ├── SparkleBridge.swift       — 单例，持有 SPUUpdater，对外暴露 checkForUpdates/downloadAndInstall/skip/dismiss/retry；Debug 下为空 stub
│   └── UpdateUserDriver.swift    — 实现 Sparkle 的 SPUUserDriver，事件 → UpdateStore 变更（MainActor，Release-only）
```

Add a row to the Common Tasks table (after the "跑测试" row or in a thematically appropriate position):

```
| 改自动更新 UI / 行为 | `mux0/Update/UpdateStore.swift`, `mux0/Update/UpdateUserDriver.swift`, `mux0/Settings/Sections/UpdateSectionView.swift`, `mux0/Sidebar/SidebarView.swift`（footer） |
| 改发布流水线 / appcast 格式 | `.github/workflows/release.yml`, `.github/scripts/render-appcast.sh`, `docs/build.md` |
```

In the "提交格式" convention line, ensure `update` is present in the scope list (add it if the current list is `sidebar | tabcontent | settings | theme | ghostty | models | metadata | bridge | build | docs`):

Change that line to:
```
5. **提交格式** `type(scope): description` — e.g. `feat(tabcontent): add drag-to-reorder`；scope 与目录对应，合法值：`sidebar | tabcontent | settings | theme | ghostty | models | metadata | bridge | build | docs | update`
```

- [ ] **Step 11.2: Mirror the same changes in `AGENTS.md`**

`AGENTS.md` is a mirror of `CLAUDE.md` per the existing doc-drift convention. Apply the identical additions (directory tree entry, Common Tasks rows, commit-scope update).

- [ ] **Step 11.3: Update `docs/architecture.md` with an Auto-Update section**

Append to `docs/architecture.md` (placement: after whatever existing section ends with infrastructure, or as a new top-level `## Auto-Update` — use whichever slot preserves the existing flow; when in doubt, add at the end before any decision-records list):

````markdown
## Auto-Update

基于 [Sparkle](https://sparkle-project.org) 2.6+。Sparkle 只负责"下载、EdDSA 校验、重启安装"引擎，UI 完全自绘以对齐 mux0 其它 settings 面板。

```
Sparkle internal ─► UpdateUserDriver (SPUUserDriver)
                       │ (MainActor mutate)
                       ▼
                   UpdateStore (@Observable)
                       │
                       ├─► SidebarView footer (红点)
                       └─► UpdateSectionView (主面板)

User click ──► SparkleBridge.{checkForUpdates | downloadAndInstall | skipVersion | dismiss | retry}
                   │
                   ▼
               SPUUpdater APIs
```

**关键约束:**
- Sparkle 符号只在 `mux0/Update/SparkleBridge.swift` 和 `UpdateUserDriver.swift` 里 `import`，与 ghostty 约定对齐。
- `UpdateStore` 是唯一写入口；所有 UI 通过它读状态。
- Debug 构建 `#if !DEBUG` 守卫掉整个 Sparkle 调用链，`SparkleBridge.isActive` 为 false，不发任何网络请求。
- Feed: `https://github.com/10xChengTu/mux0/releases/latest/download/appcast.xml`。appcast 仅含当前版本一个 `<item>`，历史版本交给 GitHub Releases 页面承载。
- 启动 3 s 后静默 check 一次；Sparkle 自带 24 h 定时器后续 check。
````

- [ ] **Step 11.4: Update `docs/settings-reference.md`**

Append a new Update section at the bottom of `docs/settings-reference.md`:

````markdown
## Update

新增在 Settings tab 条最后一位。与其它 section 不同：不读写 mux0 config 文件，状态全部活在内存（`UpdateStore`）+ Sparkle 自管的 `UserDefaults` keys。

**UI 状态（共 7 种）**：`idle`, `checking`, `upToDate`, `updateAvailable(version, releaseNotes)`, `downloading(progress)`, `readyToInstall`, `error(message)`。详见 `docs/superpowers/specs/2026-04-19-auto-update-design.md`。

**Sparkle 自管的 `UserDefaults` keys**（不在 mux0 config 文件里）：
- `SULastCheckTime` — 上次 check 时间
- `SUSkippedMinorVersion` / `SUSkippedMajorVersion` — 用户点了 "Skip This Version"
- `SUAutomaticallyUpdate` — （未使用）静默升级开关
- `SUEnableAutomaticChecks` — 由 Info.plist 设为 `YES`
- `SUScheduledCheckInterval` — 由 Info.plist 设为 86400（24h）

Debug 构建整个 section 仍然渲染，但 "Check for Updates" 按钮 disabled，并附一行 `(Auto-update is disabled in Debug builds.)` 说明。
````

- [ ] **Step 11.5: Update `docs/testing.md`**

Append a new subsection at the bottom:

````markdown
## 手动 QA：自动更新

依赖已经发布到 GitHub Releases 的 v0.1.0 + 一个本地构建的"伪低版本"。

1. 把 `project.yml` 里 `MARKETING_VERSION` 临时改成 `0.0.9`，`xcodegen generate`，构建 Release：
   ```bash
   xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Release build
   ```
2. 启动产物。~3 s 内 sidebar 左下角红点应亮起。
3. 点版本号，Settings 应直接定位到 Update section，显示 `Version 0.1.0 is available` + release notes。
4. 点 `Download & Install`：进度 0-100%，app 退出并重启。重启后版本显示 `v0.1.0`，红点消失。
5. 重复 1-3。点 `Skip This Version`：红点立刻消失，关闭 app 再开不再提醒 0.1.0。发布一个 0.1.1（测试用）后红点重新出现。
6. 断网，点 `Check for Updates`：显示红色错误卡 + Retry 按钮。
7. Debug 构建：启动后无论如何不应发 appcast 请求；Update section 的 button 为 disabled，hint 行可见。

完事把 `MARKETING_VERSION` 改回。
````

- [ ] **Step 11.6: Update `docs/build.md`**

Append a new section at the bottom:

````markdown
## Release 流程

人工 tag → GitHub Actions 自动构建 + 签名 + 发布。

### 首次发布一次性准备

```bash
# Sparkle 的 generate_keys 在 SPM fetched 的 Sparkle 里
cd ~/Library/Developer/Xcode/DerivedData/mux0-*/SourcePackages/artifacts/sparkle/Sparkle/bin
./generate_keys
# 输出两件：私钥（写入 Keychain）+ 公钥（打印到 stdout）
```

- 把 stdout 的公钥复制进 `project.yml` 的 `INFOPLIST_KEY_SUPublicEDKey`，`xcodegen generate`，提交。
- 把私钥 export 到文本（`./generate_keys -x ed25519.priv`），塞进 GitHub repo secret `SPARKLE_ED_PRIVATE_KEY`，然后删本地文件（Keychain 仍留一份）。

### 常规发布

```bash
# 先过一遍本地测试
xcodebuild test -project mux0.xcodeproj -scheme mux0Tests

# 按需手动 bump 版本（MARKETING_VERSION / CURRENT_PROJECT_VERSION）
# 修改 project.yml 后 xcodegen generate 并 commit

# 打 tag + push
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
# → .github/workflows/release.yml 触发，~10 分钟后 Release 出现在 GitHub Releases 页面
```

### Appcast 格式

单 `<item>` 格式，由 `.github/scripts/render-appcast.sh` 从 release notes + `sign_update` 输出填模板生成。详见工作流文件。
````

- [ ] **Step 11.7: Run the doc-drift checker**

```bash
./scripts/check-doc-drift.sh
```

Expected: PASS. If it reports drift, recheck that the Directory Structure tree entries in `CLAUDE.md` and `AGENTS.md` match the actual `mux0/Update/` contents exactly.

- [ ] **Step 11.8: Commit**

```bash
git add CLAUDE.md AGENTS.md docs/architecture.md docs/settings-reference.md docs/testing.md docs/build.md
git commit -m "$(cat <<'EOF'
docs: document auto-update architecture, release flow, and QA

- CLAUDE.md / AGENTS.md: add Update/ directory tree, Common Tasks rows,
  and "update" to the allowed commit-scope list.
- docs/architecture.md: new Auto-Update section with data-flow diagram.
- docs/settings-reference.md: new Update section + Sparkle-managed
  UserDefaults keys.
- docs/testing.md: manual QA procedure for the update flow.
- docs/build.md: Release subsection covering first-release bootstrap
  (generate_keys) + tag-push workflow + appcast format.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Release CI workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `.github/scripts/render-appcast.sh`

- [ ] **Step 12.1: Write the appcast render script**

```bash
mkdir -p .github/scripts
```

Write `.github/scripts/render-appcast.sh`:

```bash
#!/usr/bin/env bash
# render-appcast.sh VERSION BUILD_NUMBER DMG_PATH ED_SIGNATURE RELEASE_NOTES_PATH
# Emits appcast.xml on stdout.
set -euo pipefail

VERSION="$1"
BUILD_NUMBER="$2"
DMG_PATH="$3"
ED_SIGNATURE="$4"
RELEASE_NOTES_PATH="$5"

DMG_NAME=$(basename "$DMG_PATH")
BYTE_LENGTH=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH")
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
NOTES=$(cat "$RELEASE_NOTES_PATH")

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>mux0</title>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[${NOTES}]]></description>
      <enclosure
        url="https://github.com/10xChengTu/mux0/releases/download/v${VERSION}/${DMG_NAME}"
        sparkle:version="${BUILD_NUMBER}"
        sparkle:shortVersionString="${VERSION}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${BYTE_LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
```

Mark it executable:

```bash
chmod +x .github/scripts/render-appcast.sh
```

- [ ] **Step 12.2: Write the release workflow**

Write `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - "v*.*.*"

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0

      - name: Install toolchain
        run: |
          brew install xcodegen create-dmg git-cliff
          brew install --cask gh || true

      - name: Build libghostty
        run: ./scripts/build-vendor.sh

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Extract version from tag
        id: version
        run: |
          TAG="${GITHUB_REF#refs/tags/}"
          VERSION="${TAG#v}"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          BUILD=$(grep -E '^ +CURRENT_PROJECT_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"')
          echo "build=$BUILD" >> "$GITHUB_OUTPUT"

      - name: Build Release (arm64)
        run: |
          xcodebuild \
            -project mux0.xcodeproj \
            -scheme mux0 \
            -configuration Release \
            -arch arm64 \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY=- \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            build

      - name: Ad-hoc codesign
        run: |
          APP="build/Build/Products/Release/mux0.app"
          codesign --force --deep --sign - "$APP"

      - name: Generate changelog
        run: git-cliff --latest --strip all --output CHANGELOG.md

      - name: Create DMG
        id: dmg
        run: |
          VERSION="${{ steps.version.outputs.version }}"
          DMG="mux0-${VERSION}-arm64.dmg"
          create-dmg \
            --volname "mux0 ${VERSION}" \
            --window-size 520 320 \
            --icon-size 96 \
            --app-drop-link 380 180 \
            "$DMG" \
            "build/Build/Products/Release/mux0.app"
          echo "path=$DMG" >> "$GITHUB_OUTPUT"

      - name: Sign DMG with EdDSA
        id: sign
        env:
          ED_PRIV: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          PRIV_PATH=$(mktemp)
          echo "$ED_PRIV" > "$PRIV_PATH"
          # sign_update is bundled inside the Sparkle SPM checkout
          SIGN=$(find build/SourcePackages/artifacts/sparkle -name sign_update | head -1)
          if [ -z "$SIGN" ]; then
            echo "sign_update not found — falling back to curl prebuilt"
            curl -L -o /tmp/sign_update https://github.com/sparkle-project/Sparkle/releases/download/2.6.3/sign_update
            chmod +x /tmp/sign_update
            SIGN=/tmp/sign_update
          fi
          SIGNATURE=$("$SIGN" -f "$PRIV_PATH" "${{ steps.dmg.outputs.path }}" | awk '{print $1}')
          rm -f "$PRIV_PATH"
          echo "signature=$SIGNATURE" >> "$GITHUB_OUTPUT"

      - name: Render appcast.xml
        run: |
          .github/scripts/render-appcast.sh \
            "${{ steps.version.outputs.version }}" \
            "${{ steps.version.outputs.build }}" \
            "${{ steps.dmg.outputs.path }}" \
            "${{ steps.sign.outputs.signature }}" \
            CHANGELOG.md \
            > appcast.xml

      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "${{ steps.version.outputs.tag }}" \
            "${{ steps.dmg.outputs.path }}" \
            appcast.xml \
            --title "${{ steps.version.outputs.tag }}" \
            --notes-file CHANGELOG.md
```

- [ ] **Step 12.3: Syntax-check locally (no execution)**

```bash
# Optional but strongly recommended if actionlint is installed:
which actionlint && actionlint .github/workflows/release.yml || echo "actionlint not installed; skipping lint"
```

- [ ] **Step 12.4: Ensure the shebang/executable bit landed**

```bash
ls -l .github/scripts/render-appcast.sh
```

Expected: `-rwxr-xr-x ... render-appcast.sh`

- [ ] **Step 12.5: Commit**

```bash
git add .github/workflows/release.yml .github/scripts/render-appcast.sh
git commit -m "$(cat <<'EOF'
build(ci): add release workflow (tag-triggered, EdDSA-signed, appcast)

Trigger: push of tag matching v*.*.*
Steps: build libghostty → xcodegen → xcodebuild Release arm64 → adhoc
codesign → git-cliff changelog → create-dmg → sign_update (EdDSA) →
render appcast.xml (single-item) → gh release create.

Requires SPARKLE_ED_PRIVATE_KEY in repo secrets (set during first
release bootstrap; see docs/build.md).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Final verification

**Files:** (none — verification only)

- [ ] **Step 13.1: Full test suite**

```bash
xcodebuild test -project mux0.xcodeproj -scheme mux0Tests 2>&1 | tail -30
```

Expected: all tests PASS, including the new 9 `UpdateStoreTests` cases.

- [ ] **Step 13.2: Clean full build (Debug)**

```bash
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug clean build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 13.3: Clean full build (Release)**

```bash
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Release clean build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. This is the first time since Task 1 that we fully verify Release — ensures the Sparkle linkage, UpdateUserDriver, and Info.plist keys all line up.

- [ ] **Step 13.4: Doc drift check**

```bash
./scripts/check-doc-drift.sh
```

Expected: PASS (clean). If not, re-align the Directory Structure tree in `CLAUDE.md` / `AGENTS.md` with the actual `mux0/Update/` contents.

- [ ] **Step 13.5: Manual smoke in Debug**

```bash
xcodebuild -project mux0.xcodeproj -scheme mux0 -configuration Debug -derivedDataPath /tmp/mux0-debug build 2>&1 | tail -5
open /tmp/mux0-debug/Build/Products/Debug/mux0.app
```

Checks:
- Footer shows `v0.1.0` + gear, no red dot.
- Click version → Settings on Update section → "Check for Updates" is **disabled** + hint line visible.
- Click gear → Settings on **Appearance** section.
- Close, reopen — no network request should fire. (Confirm mentally; not worth asserting in code.)

- [ ] **Step 13.6: Final commit (if any trailing fixups)**

If 13.1-13.5 all pass with no outstanding changes: no commit needed — plan is complete. If fixups were needed:

```bash
git add -u
git commit -m "fixup(update): post-integration cleanup from final verification"
```

---

## Post-Plan: First Release Bootstrap (HUMAN)

The plan above leaves the `SUPublicEDKey` placeholder in `project.yml`. Before tagging `v0.1.0`:

1. Run `generate_keys` (see `docs/build.md`).
2. Paste the public key into `project.yml`, `xcodegen generate`, commit as a separate change: `build(update): fill Sparkle EdDSA public key`.
3. Add the private key to GitHub repo secrets as `SPARKLE_ED_PRIVATE_KEY`.
4. `git tag -a v0.1.0 -m "Release v0.1.0"` then `git push origin v0.1.0`.
5. Watch Actions complete; verify the Release page has `mux0-0.1.0-arm64.dmg` and `appcast.xml` attached.
6. Manually download the DMG and install into `/Applications`. Gatekeeper warning is expected for adhoc-signed first install; right-click → Open.

The plan's implementation tasks can be merged to master **before** step 1 is done — the Debug-build users will not notice, and the presence of the placeholder key is documented in-file.
