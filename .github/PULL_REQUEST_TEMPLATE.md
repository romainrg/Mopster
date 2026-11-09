## Summary

<!-- What does this pull request change, and why? Link the issue it addresses, for example: Fixes #42 -->

## Type of change

- [ ] Bug fix
- [ ] New feature or module
- [ ] Cleanup rule or maintenance task
- [ ] Translation
- [ ] Refactoring (no behavior change)
- [ ] Documentation
- [ ] Build or CI

## How was this tested?

<!-- Commands you ran (`make test`), and manual steps with your macOS version and Mac (Apple Silicon or Intel). Removals only on fixtures, never on your real data. -->

## Screenshots

<!-- Required for UI changes: render them with `make screenshots`, in light and dark (and French when strings changed). -->

## Checklist

- [ ] `make test` passes locally (it includes `make check-strings`) and the build has no new warnings
- [ ] Logic lives in `MopsterCore` with unit tests (bug fixes with a regression test)
- [ ] Every removal goes through `SafetyGuard` and the Trash
- [ ] New user-facing strings are in `Localizable.xcstrings` with French
- [ ] User-visible changes are listed in `CHANGELOG.md` under **Unreleased**
- [ ] Documentation (README in English and French, `docs/`, `AGENTS.md`) is updated if behavior, commands or rules changed
- [ ] No new dependency, network access or entitlement
- [ ] The pull request title follows Conventional Commits (`feat: ...`, `fix: ...`)

## AI assistance

<!-- "None", or which tool you used and for what. You remain responsible for every line. -->
