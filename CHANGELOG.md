# Changelog

All notable changes to Mopster are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- New look: a soft polychrome background, one gradient color per module, translucent cards and gradient primary buttons, in light and dark mode.
- Smart Sweep opens on a health score from 0 to 100 with a one-line summary, next to the startup disk's used space, memory pressure and the Trash size.
- The welcome sheet introduces the modules and explains Full Disk Access side by side.

## [0.1.0] - 2026-11-08

### Added

- Smart Sweep: one-pass overview with a card per area; Run only moves the pre-selected safe junk to the Trash.
- System Junk: declarative cleanup rules for caches, logs, crash reports, Xcode and developer caches, Mail downloads, saved state, installers and device backups, with safe and review risk levels.
- Protection: security checklist (SIP, Gatekeeper, FileVault, firewall, XProtect, automatic updates) and inspection of launch agents and daemons with code signature and review flags.
- Optimization: heavy processes with Quit and Force Quit, memory and CPU load, and background items that can be disabled or enabled.
- Maintenance: declarative maintenance tasks (RAM, DNS, Spotlight, Launch Services, font and Quick Look caches, startup disk check) run in one batch behind a single password prompt.
- Uninstaller: apps with their leftovers, Uninstall and Reset actions, and review-only leftovers of apps already deleted.
- Updater: Mac App Store apps, Sparkle apps and pending macOS updates.
- Telescope: visual disk map with drill-down.
- Large & Old Files and Duplicates, with Quick Look, Reveal in Finder and a guard that always keeps one copy.
- Safety model: every removal goes through `SafetyGuard` and the Trash, with a Finder fallback for root-owned items; Mopster never empties the Trash. Structural folders and secret stores are protected, symlinks are resolved, and the guard fails closed.
- English and French interface.
- Demo mode (`make demo`) with sample data and no disk access.
- DMG and PKG installers, with `SHA256SUMS`, built by `make release` and published by the release workflow.
