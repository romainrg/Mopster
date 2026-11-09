# Architecture

This document explains how Mopster is built: its modules, how a feature is wired, and the safety model. Read it before changing removal or scanning. Commands and contribution rules are in [CONTRIBUTING.md](../CONTRIBUTING.md) and [AGENTS.md](../AGENTS.md).

## Overview

- **Platform**: macOS 14 or later, universal binary, not sandboxed (a cleaner has to read `~/Library` and other apps' data), hardened runtime, ad hoc signed.
- **Stack**: Swift in Swift 5 language mode, SwiftUI with AppKit where needed. Apple frameworks only, no third-party dependencies.
- **Project**: `project.yml` (XcodeGen) generates `Mopster.xcodeproj`. All logic lives in a local Swift package, `MopsterCore`, which has no SwiftUI or AppKit and is tested without a host app.
- **Pattern**: MVVM with `@Observable`. Services are reached through `AppEnvironment`, which has a live and a demo variant.

## Layers

| Layer | Location | Responsibility |
|---|---|---|
| Core | `MopsterCore/Sources/MopsterCore` | Safety guard, removal, rules, scanners, parsers, scan flow state machine |
| App | `Mopster/App` | `AppEnvironment`, `FeatureModels`, window and sidebar |
| Features | `Mopster/Features/<Module>` | One view and one view model per module |
| Shared views | `Mopster/Shared` | `FeatureScaffold`, `CleanupResultsView`, context menu, Quick Look, Finder trash, Full Disk Access |
| Demo | `Mopster/Demo` | Sample data and demo implementations of every service |
| Screenshots | `Tools/Screenshots` | Offscreen renderer for the README images; never shipped |

## Core modules

| Folder | Contents |
|---|---|
| `Safety/` | `SafetyGuard`, `ProtectedPaths` |
| `Removal/` | `ItemRemover`, `TrashRemover`, `IgnoreList`, `AppleScriptQuoting` |
| `Junk/` | `JunkCatalog`, `JunkRule`, `JunkScanner` |
| `Maintenance/` | `MaintenanceCatalog`, `MaintenanceTask`, `MaintenanceBatch`, `LiveMaintenanceRunner` |
| `Launchd/`, `Protection/` | Launch items, `Launchctl`, code signatures, known adware list, security checklist and parsers |
| `Processes/` | Process sampler, system load, process control policy |
| `Apps/` | App inventory, leftover finder, orphan detector |
| `Updates/` | `AppVersion`, App Store lookup, appcast parser, `softwareupdate` parser, `UpdateChecker`, `HTTPClient` |
| `Disk/`, `Files/` | `SizeTree` (BSD `fts`), `Treemap`, large-file and duplicate finders |
| `Flow/` | `ScanFlow`, selection, cleanup model |
| `Support/` | `L(...)` localized strings, path patterns, disk usage, process runner |

## Scan flow

Every module shares the same phases: intro, scanning, results, done. `ScanFlow` (core) is the state machine; `FeatureScaffold` and `CleanupResultsView` render it. Previews and screenshot scenes start in a later phase with `ScanFlow(initialPhase:scan:)`.

A view model owns its `ScanFlow` and adopts the scan result itself inside the scan closure. View models are owned by `FeatureModels`, one per `AppEnvironment`, so state survives sidebar navigation.

Scanners that honor the ignore list are created per scan, through factories on `AppEnvironment` (for example `junk: (IgnoreList) -> any JunkScanning`), so they read the current list at scan time.

## Live and demo environments

`AppEnvironment.live()` wires the real services. `AppEnvironment.demo()` (launch argument `--demo`, `make demo`) wires the implementations in `Mopster/Demo`, which return sample data and simulate actions without touching the disk. Every feature must work in both. Screenshots and previews are built from the demo environment, so no personal data appears in them.

A Debug-only launch argument, `--fixture-home <path>`, points the live environment at a fake home for manual removal tests.

## Safety model

- `SafetyGuard` validates every item at removal time. Symlinks are resolved, the path must be inside an allowed root (home, `/Applications`, the listed `/Library` locations, a user-chosen Telescope root), never a protected path, never Mopster itself. It fails closed.
- Inside the home, structural folders (the home itself, the standard folders, every direct child of `~/Library`) are never removable themselves, only their contents. Secret stores (`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, Keychains, iCloud Drive) are off-limits entirely. The list is a Swift array in `ProtectedPaths`.
- Removal is `FileManager.trashItem`. When Mopster isn't allowed to move an item itself (for example files owned by the system), Finder is asked to delete the item through AppleScript; it prompts for the administrator password and still uses the Trash. Paths are quoted so they are never interpreted.
- The guard runs at removal time on every item, whatever the scan saw. Telescope and Duplicates also pre-check with the same guard to disable the rows it would refuse. An item that vanished is reported as already gone; one swapped for a symlink to a protected path is refused.
- Mopster never empties the Trash. The Done screen says so and offers to open it.
- Orphaned leftovers are review-only and unselected. The uninstaller checks other installed apps before claiming a leftover. Duplicates always keep at least one copy.
- Maintenance tasks run through one batch behind a single standard password prompt, and every executable they use is on an allowlist enforced by a test.

## Cleanup rules and maintenance tasks

Both are declarative Swift arrays: `JunkCatalog.rules` and `MaintenanceCatalog`. In `JunkCatalog`, the order is both the claim order and the display order: a more specific rule claims its paths before a general one, so the same bytes are never counted twice. See the "Add a cleanup rule" and "Add a maintenance task" sections of [AGENTS.md](../AGENTS.md).

## Localization

A single String Catalog, `Mopster/Resources/Localizable.xcstrings`, English as the source and French complete. Core types expose `LocalizedStringResource` through `L(key, default)`, resolved from the app bundle. Keys are added to the catalog by hand; `make check-strings` and `LocalizationCoverageTests` fail when a key is missing or has no French value.

## Network

The Updater is the only module that uses the network: the public iTunes lookup API (App Store apps), the apps' own Sparkle feeds over https, and `softwareupdate --list` for macOS. Requests are limited in parallel and time out. There is no analytics or telemetry. To check for updates, Mopster sends the bundle identifiers of the user's App Store apps and the country to Apple's iTunes lookup service (`AppStoreLookup`), and fetches each Sparkle app's own update feed. Nothing else leaves the Mac.

## Distribution

`scripts/build-release.sh` builds a universal Release app, re-signs it ad hoc with the hardened runtime, and writes the DMG, the PKG and `SHA256SUMS` to `build/release/`. See [RELEASING.md](RELEASING.md).
