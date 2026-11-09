# Contributing to Mopster

Thanks for your interest in Mopster! This guide explains how to set up the project, the rules every change follows, and how pull requests are reviewed.

By taking part, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug**: open an issue with the *Bug report* template, after checking that it has not been reported already. Reports from Intel Macs and from macOS versions other than 27 are especially welcome: those are untested by hand.
- **Suggest a feature**: open an issue with the *Feature request* template. For anything bigger than a small fix, discuss it in an issue **before** writing code, so we agree on the approach first.
- **Propose a cleanup rule**: use the *Cleanup rule* template, or open a pull request straight away (see "Add a cleanup rule" in [AGENTS.md](AGENTS.md)).
- **Fix or build something**: issues labeled `good first issue` and `help wanted` are good starting points. Comment on the issue to say you are working on it.
- **Translate the app**: see [Adding a language](#adding-a-language).
- **Report a security issue privately**, never in a public issue: see [SECURITY.md](SECURITY.md).

## Development setup

Requirements: macOS 14 or later, Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/<your-account>/mopster.git
cd mopster
make build      # generates Mopster.xcodeproj from project.yml, then builds
make run        # opens the app
```

| Task | Command |
|---|---|
| Generate the Xcode project | `make generate` |
| Build (Debug) | `make build` |
| All tests, then the strings check | `make test` |
| Core tests only (faster) | `make core-test` or `make core-test FILTER=SafetyGuardTests` |
| Check French translations | `make check-strings` |
| Run with sample data, touching nothing | `make demo` |
| Render the README scenes | `make screenshots` |
| Universal DMG and PKG | `make release` |

Good to know:

- `project.yml` is the source of truth. Run `make generate` again after adding, removing or renaming a file. Never commit `Mopster.xcodeproj` and never edit `Mopster/Resources/Info.plist`: both are generated.
- The `Makefile` finds Xcode when `xcode-select` points to the Command Line Tools.
- Development builds are signed ad hoc, and macOS ties Full Disk Access to the exact build. After a rebuild, remove Mopster from System Settings > Privacy & Security > Full Disk Access and add it again, or scans will skip protected places.
- **Never test removals on your real files.** Use `make demo` (nothing touches the disk) or a fixture home: `scripts/fixture-home.sh <new-empty-dir>` creates a fake home, and a Debug build launched with `--fixture-home <dir>` uses it. Trashed fixture files land in your real Trash.

## Project structure

| Path | Contents |
|---|---|
| `MopsterCore/` | Swift package with all the logic: safety guard, removal, cleanup rules, maintenance tasks, scanners, updates parsing. No SwiftUI or AppKit. |
| `MopsterCore/Tests/MopsterCoreTests/` | Unit tests (XCTest), on temporary directories. |
| `Mopster/` | The app target: views, view models, `AppEnvironment` (live and demo), `FeatureModels`, shared views, demo data, resources. |
| `Tools/Screenshots/` | Development tool that renders the README images offscreen. |
| `scripts/` | Release, release-notes, strings check, screenshots and fixture scripts. |
| `docs/` | Architecture and release documentation, images. |

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing removal or scanning, and the "Module pattern" in [AGENTS.md](AGENTS.md) before adding a feature.

## Rules for every change

These rules keep Mopster safe, small and maintainable. A change that breaks one of them needs to be discussed in an issue first.

### Safety

- Every removal goes through `SafetyGuard` and ends in the Trash (`FileManager.trashItem`, Finder as the fallback for root-owned items). Mopster never empties the Trash, never shreds, never touches system paths.
- The user sees and selects what is removed. Anything uncertain is a `review` item, unselected by default.
- Maintenance tasks never delete user data, and every command they run is on the allowlist in `MaintenanceBatchTests`.
- Paths are data: they are never interpreted as shell, AppleScript or glob syntax.
- No analytics and no new network access. The only calls are the update checks.
- No third-party dependencies, no new entitlements, no change to the bundle identifier.

### Code

- Logic lives in `MopsterCore`, with unit tests. The app target holds UI and macOS integration.
- MVVM with `@Observable`. No new singletons. View models live in `FeatureModels`.
- Services are reached through `AppEnvironment`, with a live and a demo implementation, so every feature works in demo mode.
- Swift 5 language mode. The build must stay free of warnings. 4-space indentation, `// MARK: -` sections.
- Comments and documentation are in English. Keep comments minimal.
- Put `#Preview` blocks last in a file (the strings check skips what follows the first one).

### Tests

- Every logic change in `MopsterCore` comes with tests. A bug fix comes with a test that fails without the fix.
- Tests use temporary directories and never touch the real home folder.
- UI changes are checked with `make screenshots`: open the PNGs and look at light, dark and French.

## Adding a language

English is the source language and French is complete. Strings live in a single String Catalog, `Mopster/Resources/Localizable.xcstrings`, shared by the app and by the core types.

Option 1, in Xcode:

1. Run `make generate` and open `Mopster.xcodeproj`.
2. Select `Localizable.xcstrings`, click **+** at the bottom of the language list and pick your language.
3. Translate every key, mind plural variants (`%lld items`) and keep placeholders such as `%@` and `%lld` intact.

Option 2, with export and import:

```sh
xcodebuild -exportLocalizations -project Mopster.xcodeproj -localizationPath build/loc -exportLanguage de
# translate build/loc/de.xcloc, then
xcodebuild -importLocalizations -project Mopster.xcodeproj -localizationPath build/loc/de.xcloc
```

Note that `-exportLocalizations` reformats `Localizable.xcstrings` as a side effect: check `git status` and restore the file with `git checkout Mopster/Resources/Localizable.xcstrings` before importing.

Then:

- Add the language code to `CFBundleLocalizations` in `project.yml` (then `make generate`), and note it in `README.md`, `README.fr.md` and `CHANGELOG.md`.
- Run `make test`. `make check-strings` currently requires a French value for every key; when you add a language, extend `scripts/check-strings.sh` and `LocalizationCoverageTests` so the new language is held to the same standard.
- Check the result with `make run` after switching the system language, and render it with `scripts/screenshots.sh build/screenshots --language <code>` to catch truncated labels.

## Commits and branches

- Work on a branch of your fork, created from `main`: `feat/short-description`, `fix/short-description`, `docs/short-description`...
- Write [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `build:`, `ci:`, `docs:`, `test:` or `chore:`. Use the imperative mood, keep the subject under 72 characters, and reference issues in the body (`Fixes #42`).
- Keep commits focused, and rebase on `main` rather than merging `main` into your branch.

## Pull requests

1. One topic per pull request. Prefer small pull requests and split larger work.
2. Fill in the pull request template, including how you tested and screenshots (light and dark) for any UI change.
3. Make sure `make test` passes and the build has no warnings. CI runs the tests and a universal Release build on every pull request.
4. Add a line to `CHANGELOG.md` under **Unreleased** for any user-visible change.
5. Update the documentation (both READMEs, `docs/`, `AGENTS.md`) when behavior, commands or rules change.
6. Do not change the version number: the maintainer handles releases.

The maintainer reviews every pull request. Questions and change requests are a normal part of review, not a rejection. Pull requests are squash-merged, so their title must be a valid Conventional Commit message.

## AI-assisted contributions

AI coding assistants are welcome. [AGENTS.md](AGENTS.md) gives them the project's commands and rules (Claude Code reads it through `CLAUDE.md`).

- You are responsible for every line you submit: read it, understand it and test it.
- Say in the pull request which tool you used, and for what.
- Do not submit unreviewed bulk changes, images that do not show the real app, or code you cannot explain.

## Releases

The maintainer publishes releases by pushing a `vX.Y.Z` tag: see [docs/RELEASING.md](docs/RELEASING.md).

## License

By contributing, you agree that your contributions are released under the [MIT License](LICENSE).
