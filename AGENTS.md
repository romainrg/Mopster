# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, GitHub Copilot, Cursor, Gemini...) working on Mopster. Humans should read [CONTRIBUTING.md](CONTRIBUTING.md); this file summarizes the same rules in an actionable form.

## Project

Mopster is a free, open-source macOS maintenance app: it cleans junk, checks the Mac's security settings, uninstalls apps with their leftovers, finds large, old and duplicate files, maps disk usage and runs maintenance tasks. Swift and SwiftUI (AppKit where needed), macOS 14+, universal binary, not sandboxed, no third-party dependencies, English and French.

## Commands

Run them from the repository root. The `Makefile` finds Xcode even when `xcode-select` points to the Command Line Tools. XcodeGen is required (`brew install xcodegen`).

```sh
make generate                          # xcodegen generate; after adding, removing or renaming a file, or editing project.yml
make build                             # Debug build
make test                              # all tests through xcodebuild, then make check-strings
make core-test                         # MopsterCore tests only, with swift test (faster)
make core-test FILTER=SafetyGuardTests # one test class
make check-strings                     # every string the compiler extracted has a French translation in the catalog
make run                               # build and open the app
make demo                              # launch with --demo: sample data, no disk access
make screenshots                       # render the README scenes offscreen into build/screenshots
make release                           # universal build; writes build/release/Mopster-<v>.dmg, .pkg and SHA256SUMS
make clean
```

`make check-strings` reads the compiler output of the last Debug build: run `make build` first (`make test` does it for you).

## Map

- `project.yml`: XcodeGen spec and source of truth. `Mopster.xcodeproj` and `Mopster/Resources/Info.plist` are generated and git-ignored.
- `MopsterCore/Sources/MopsterCore/`: all the logic, with no SwiftUI or AppKit.
  - `Safety/`: `SafetyGuard`, `ProtectedPaths`.
  - `Removal/`: `ItemRemover`, `TrashRemover` (Trash, Finder fallback), `IgnoreList`, `AppleScriptQuoting`.
  - `Junk/`: `JunkCatalog` (the rules), `JunkRule`, `JunkScanner`.
  - `Maintenance/`: `MaintenanceCatalog` (the tasks), `MaintenanceTask`, `MaintenanceBatch`, `LiveMaintenanceRunner`.
  - `Launchd/`, `Protection/`: persistence items, code signatures, known adware list, security checklist.
  - `Processes/`: process sampler, system load, control policy.
  - `Apps/`: inventory, leftover finder, orphan detector.
  - `Updates/`: version comparison, App Store lookup, Sparkle appcast parser, `softwareupdate` parser.
  - `Disk/`, `Files/`: size tree, treemap layout, volume capacity, large-file and duplicate finders.
  - `Flow/`: `ScanFlow` (intro, scanning, results, done), selection, cleanup model, Smart Sweep's `HealthScore`.
  - `Support/`: `L(...)` localized strings, path patterns, disk usage, process runner.
- `MopsterCore/Tests/MopsterCoreTests/`: XCTest suites on temporary directories; helpers in `TestSupport.swift`.
- `Mopster/`: app target.
  - `App/`: `AppEnvironment` (live and demo services), `FeatureModels`, `ContentView`, sidebar.
  - `Features/<Module>/`: one folder per module, with its view and view model.
  - `Shared/`: `Theme` (ground, `ModuleTint` per module, `themeCard`/`themePanel`, `.gradient` and `.soft` buttons, `ModuleHeader`, `ModuleFooter`), `FeatureScaffold`, `CleanupResultsView`, context menu, Quick Look, Finder trash, Full Disk Access.
  - `Demo/`: sample data and demo implementations of every service.
  - `Onboarding/`, `Settings/`, `Resources/` (`Localizable.xcstrings`, assets).
- `Tools/Screenshots/`: offscreen renderer for the README images (development only, never shipped); scenes in `Scenes.swift`.
- `scripts/`: release build, release notes, strings check, screenshots, fixture home.
- `docs/ARCHITECTURE.md`: modules, data flow, safety model. Read it before touching removal or scanning.

## Invariants

Never break these. If a task seems to require it, stop and ask the human.

1. **Removal means the Trash.** Use `FileManager.trashItem`, with Finder as the fallback when Mopster isn't allowed to move an item itself, and always after `SafetyGuard`. Never `removeItem`, never `rm`, never a secure-delete. Mopster never empties the Trash.
2. **`SafetyGuard` runs at removal time** on every item. Telescope and Duplicates also pre-check with it to disable rows it would refuse. A vanished item is "already gone", not an error; an item swapped for a symlink to a protected path is refused. Symlinks are resolved and the guard fails closed.
3. **Protected paths.** Structural folders (home, Desktop, Documents, Library and every direct child of `~/Library`...) are never removable themselves, only their contents. Secret stores (`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, Keychains, iCloud Drive) are off-limits entirely. Never touch `/System`, `/usr`, `/bin`, `/sbin`, `/private/var/db`, app bundle contents, or Mopster itself.
4. **Nothing unseen is removed.** The user sees and selects every item. Smart Sweep's card shows the count and size of the safe junk; Run moves exactly the pre-selected safe items after a confirmation showing the total, and Review opens System Junk to see each item. `review` items start unselected. Orphaned leftovers are review-only and unselected. Duplicates always keep at least one copy; hard links are not duplicates.
5. **The uninstaller considers other installed apps** when matching leftovers, so one app's removal never takes another's data.
6. **Maintenance tasks never delete user data.** Each step's executable must be in the allowlist of `MaintenanceBatchTests.testEveryStepUsesAnAllowedExecutable`. Extend that list deliberately, with a justification in the PR. Arguments are escaped and never interpreted.
7. **Paths are data.** Spaces, quotes, backslashes, emoji and NFD Unicode pass through AppleScript, `launchctl` and glob expansion unchanged and unexecuted. Symlinks inside scanned trees are never followed.
8. **Scans survive hostile disks.** Unreadable or vanishing folders are skipped, reported as skipped, and the rest is still returned.
9. **Network.** The only network calls are the iTunes lookup API, the apps' own Sparkle feeds over https, and `softwareupdate`. No analytics, no telemetry, no new network access.
10. **No third-party dependencies.** Apple frameworks only; no Swift packages. `MopsterCore` imports Foundation, Observation, CryptoKit, Security, UniformTypeIdentifiers, CoreServices, CoreGraphics and Darwin/libproc, never SwiftUI or AppKit.
11. **Not sandboxed, hardened runtime on, ad hoc signed.** Do not add entitlements or change the signing settings. Do not change the bundle identifier `io.github.romainrg.Mopster`.
12. **Localization.** English is the source language and French is complete. Every user-facing string goes through `Localizable.xcstrings`.
13. **Author hygiene.** Nothing in code, metadata, docs, screenshots or commits mentions an employer or any company. Only "Romain Gallien" and the `romainrg` account appear.
14. **Demo isolation.** Demo mode goes through `AppEnvironment.demo()` only: it must never read or write the real disk.
15. **Both READMEs stay in sync**: `README.md` and `README.fr.md` have the same sections in the same order.

## Conventions

- Code comments and documentation in **English**, identifiers in English. Keep comments minimal: code should explain itself.
- Logic and rules in `MopsterCore`; views, view models and macOS integration in `Mopster/`. Views are `@Observable` MVVM, with no new singletons.
- **Per-scan factories.** Ignore-aware scanners are created per scan through `AppEnvironment` factories (for example `junk: @Sendable (IgnoreList) -> any JunkScanning`) that read `env.ignoreList.list` at scan time.
- **`FeatureModels`.** Each module's view model lives in `FeatureModels` (`@MainActor @Observable`, owned by `ContentView`, one per `AppEnvironment`) so state survives sidebar navigation. A view model adopts scan results itself, inside the scan closure; views do not use an `onChange` contract.
- `ScanFlow(initialPhase:scan:)` lets previews and screenshot scenes start in `.results` or `.done`.
- **Strings are added by hand.** xcodebuild does not add new keys to `Localizable.xcstrings`. Add each key in the exact format the compiler extracts (for example `%lld items found`, `Moved %@ to the Trash`) with a complete French value, then run `make build && make check-strings`.
- Put `#Preview` blocks **last** in a file: `check-strings` ignores strings after the first `#Preview`.
- Zero build warnings. 4-space indentation, `// MARK: -` sections (see `.editorconfig`).
- Conventional Commits: `feat:`, `fix:`, `build:`, `ci:`, `docs:`, `test:`, `chore:`.

## Module pattern

Every feature follows the same steps. Look at an existing module such as Large & Old Files or Duplicates and mirror it.

1. **Core scanner, protocol and tests.** In `MopsterCore`, write the logic behind a protocol (`FooScanning`) with a live implementation, and unit tests on temporary directories. Cover the hostile cases of the invariants (symlinks, unreadable folders, odd file names). Run `make core-test FILTER=FooTests`.
2. **`AppEnvironment` factory.** Add the service as a property of `AppEnvironment`, set in both `live()` and `demo()`. Ignore-aware scanners are per-scan factories. Add the demo implementation in `Mopster/Demo/` using the sample data.
3. **View model in `FeatureModels`.** Create `FooViewModel` in `Mopster/Features/Foo/`, add it to `FeatureModels`, and make it adopt scan results inside the `ScanFlow` scan closure.
4. **View with shared components.** Build `FooView` on `FeatureScaffold`, `CleanupResultsView`, `ItemContextMenu` and the other `Shared/` views so the module gets the intro, scanning, results and done phases for free. Use the theme: `ModuleHeader` on top, lists in `.themePanel()`, `ModuleFooter` with one `.gradient` primary action and `.soft` secondary ones. Add a `SidebarSection` case with its `ModuleTint` and wire it in `ContentView`.
5. **Strings.** Add every new key with French to `Localizable.xcstrings`, then `make build && make check-strings`.
6. **Screenshot scene.** Register a scene in `Tools/Screenshots/Scenes.swift` (built from demo data, for example `foo-results`), run `make screenshots`, **open the PNGs** and check them in light, dark and French (`scripts/screenshots.sh build/screenshots foo --language fr`). Fix anything truncated, overlapping or untranslated.
7. **Wrap up.** Add the module to the README features (both languages), to `CHANGELOG.md` and to `docs/ARCHITECTURE.md`.

## Add a cleanup rule

Rules are declarative entries of `JunkCatalog.rules` in `MopsterCore/Sources/MopsterCore/Junk/JunkCatalog.swift`.

1. Add a `JunkRule` with an `id` (unique camelCase), `title` and `explanation` through `L("junk.<id>.title", "...")`, an SF Symbol, `locations` (each starting with `~`, simple `*` globs), optional `exclusions`, `minAge` or `extensions`, `needsFullDiskAccess`, and a `risk`: `.safe` only when the owning app rebuilds the data, otherwise `.review` (unselected by default).
2. **Claim order matters.** The array is ordered most specific first, and the order is both the claim order and the display order: a rule claims its paths before a more general one can count them. Insert a specific rule above the general rule that would otherwise cover the same folder (for example browser caches above app caches).
3. Add the French strings to `Localizable.xcstrings`.
4. Tests: `JunkCatalogTests` already checks that ids are unique, locations start with `~`, items pass `SafetyGuard` and strings are localized. Add a `JunkScannerTests` case when the rule has a filter or an overlap with another rule. `LocalizationCoverageTests` fails when a key has no French translation.
5. Run `make core-test FILTER=JunkCatalogTests`, then `make test`. Add a line to `CHANGELOG.md`.

## Add a maintenance task

Tasks are declarative entries of `MaintenanceCatalog` in `MopsterCore/Sources/MopsterCore/Maintenance/MaintenanceCatalog.swift`.

1. Add a `MaintenanceTask` with an `id` (shell-safe, unique), `title`, `explanation`, `steps` (each step is an executable followed by its arguments), `needsAdmin`, and where relevant `restartAdvised`, `showsOutput` or an `isAvailable` check for OS versions that lack the tool.
2. A task never deletes user data. If a command removes anything outside a cache the system rebuilds, it does not belong here.
3. **Extend the allowlist deliberately.** `MaintenanceBatchTests.testEveryStepUsesAnAllowedExecutable` lists the permitted executables. A new executable fails the test until you add it to that list, in the same PR, with a justification.
4. Add the French strings, run `make core-test FILTER=MaintenanceBatchTests`, then `make test`. Add a line to `CHANGELOG.md`.

## Definition of done

- `make test` passes (unit tests and `make check-strings`) with no new warnings.
- Logic changes have unit tests in `MopsterCoreTests`; bug fixes include a regression test that fails without the fix.
- New strings exist in French. UI changes were rendered with `make screenshots` and the PNGs were opened and checked in light, dark and French.
- Do not run removals against the real home folder while testing: use fixtures (`scripts/fixture-home.sh`, the Debug-only `--fixture-home <path>` launch argument) or `make demo`. Trashed fixture files land in the real Trash.
- Do not trigger permission prompts or drive the UI through automation; list manual test steps for the human.
- User-visible changes have an entry under **Unreleased** in `CHANGELOG.md`. Documentation (both READMEs, `docs/`, this file) is updated when commands, behavior or rules change.
- Do not bump versions, create tags, push, or edit the release workflow or signing settings unless explicitly asked.
- Pull requests follow `.github/PULL_REQUEST_TEMPLATE.md`, including the *AI assistance* section.
