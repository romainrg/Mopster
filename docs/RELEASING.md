# Releasing

Mopster follows [Semantic Versioning](https://semver.org). The version lives in `project.yml`: `MARKETING_VERSION` (for example `0.2.0`) and the build number `CURRENT_PROJECT_VERSION`.

## Publishing a release

1. On a branch from `main`, move the **Unreleased** entries of `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading and update the comparison links at the bottom of the file.
2. In `project.yml`, set `MARKETING_VERSION` to `X.Y.Z` and increment `CURRENT_PROJECT_VERSION`.
3. Check locally:

   ```sh
   make test                         # unit tests and strings check
   make release                      # universal build, signature checks, DMG, PKG and SHA256SUMS in build/release/
   scripts/release-notes.sh X.Y.Z    # notes that will be published
   ```

   `make release` fails unless the binary is universal (arm64 and x86_64) and the ad hoc signature carries the hardened runtime flag. Open the DMG and the PKG once and run `shasum -a 256 -c SHA256SUMS` from `build/release/`.

4. Commit (`chore: release X.Y.Z`), open a pull request and merge it once CI passes.
5. Tag the merge commit and push the tag:

   ```sh
   git switch main && git pull
   git tag -a vX.Y.Z -m "Mopster X.Y.Z"
   git push origin vX.Y.Z
   ```

6. The **Release** workflow (`.github/workflows/release.yml`) checks that the tag matches `MARKETING_VERSION`, runs the tests, builds the universal app and publishes a GitHub release with `Mopster-X.Y.Z.dmg`, `Mopster-X.Y.Z.pkg`, `SHA256SUMS` and the changelog notes.

If the workflow fails, fix the problem on `main`, delete the tag (`git push --delete origin vX.Y.Z` and `git tag -d vX.Y.Z`), then tag again.

## Hands-on test

### Automated (2026-11-08)

Run on Apple Silicon, macOS 27.0.1, Xcode 16.2 (from `sw_vers` and `xcodebuild -version`). Nothing was installed into `/Applications`. No `installer` or `sudo` was used; the app was only launched and quit for the smoke tests below.

- `make test`: 251 tests, 0 failures, `** TEST SUCCEEDED **`, `check-strings: OK (105 files)`.
- `make release`: produced `build/release/Mopster-0.1.0.dmg`, `build/release/Mopster-0.1.0.pkg` and `build/release/SHA256SUMS` (`(x86_64 arm64)`). The output also contained four `write: Permission denied` lines of unidentified origin; the build exited 0 and every check below passed.
- DMG, mounted with `hdiutil attach -readonly -nobrowse -mountpoint <tmp>`: lists `Applications -> /Applications` (symlink) and `Mopster.app`; `codesign --verify --strict` passes; `codesign -dv` shows `flags=0x10002(adhoc,runtime)`; `lipo -archs` gives `x86_64 arm64`; `CFBundleShortVersionString` is `0.1.0`; the image detached cleanly.
- PKG, after `pkgutil --expand`: Distribution has `os-version min="14.0"` and `hostArchitectures="arm64,x86_64"`; PackageInfo has `install-location="/Applications"` and `relocatable="false"`. It still contains an empty `<relocate/>` element, which `pkgbuild` always writes and which lists no bundle to relocate. `pkgutil --payload-files` contains `./Mopster.app/Contents/MacOS/Mopster`.
- `shasum -a 256 -c SHA256SUMS`: `Mopster-0.1.0.dmg: OK`, `Mopster-0.1.0.pkg: OK`.
- Launch smoke test of `build/Build/Products/Release/Mopster.app`: after `open`, `pgrep -x Mopster` succeeded 10 s later; the same with `open … --args --demo` (the process ran with `--demo`). The second run quit cleanly with `osascript -e 'quit app "Mopster"'`; the first needed `pkill -x Mopster` after the AppleScript quit returned error -128. Nothing was left running.
- `scripts/release-notes.sh 0.1.0` prints the notes, including both the DMG and the PKG install paths.

### Manual checklist (to do before publishing)

- [ ] Install from the DMG (drag `Mopster.app` to `/Applications`) and launch it.
- [ ] Install the PKG over it (`sudo installer -pkg build/release/Mopster-0.1.0.pkg -target /`, which needs the password).
- [ ] Check the installed version is 0.1.0.
- [ ] Gatekeeper **Open Anyway** on a downloaded copy.
- [ ] Grant Full Disk Access.
- [ ] Run each of the 10 modules on real data, read-only scans.
- [ ] Maintenance password prompt with Flush DNS and Quick Look reset.
- [ ] Uninstall a fixture app (`scripts/fixture-home.sh` plus a copied tiny app).
- [ ] System Junk clean on the fixture home via `--fixture-home` in a Debug build.
- [ ] Telescope on an external volume, if available.
- [ ] The French UI.
- [ ] Root-owned uninstall: `sudo cp -R` a tiny app into `/Applications`, uninstall it in Mopster, and confirm the Automation prompt, the password prompt and that it lands in the Trash.
- [ ] A pass on a user account without Full Disk Access: watch for TCC prompts and check the skipped-locations notes.
- [ ] After the PKG install, `ls -la /Applications | grep '\._'` and `find /Applications/Mopster.app -name '._*'` print nothing.
- [ ] Cmd-Q while the first-launch onboarding sheet is showing (a -128 was seen in the automated smoke test).

## Signing

Release builds are signed **ad hoc** with the hardened runtime and are not notarized: they run on any Mac, but Gatekeeper blocks the first open until the user clicks **Open Anyway** (System Settings > Privacy & Security), and macOS ties Full Disk Access to the exact build, so it must be granted again after each update. The README explains both to users.

## Planned distribution channels

None of these is set up yet; each requires a paid Apple Developer Program membership.

- **Developer ID signing and notarization** of the GitHub releases, which removes the Gatekeeper warning and keeps Full Disk Access across updates.
- **Homebrew cask**, once releases are notarized.
- **Mac App Store**: needs its own design (sandbox, reduced feature set).
