# Security policy

Mopster moves files to the Trash and runs a few system commands, so security and safety reports are taken seriously.

## Supported versions

Only the [latest release](https://github.com/romainrg/mopster/releases/latest) receives security fixes.

## Reporting a vulnerability

**Please do not open a public issue.** Report the problem privately through GitHub: [report a vulnerability](https://github.com/romainrg/mopster/security/advisories/new) (Security tab > Advisories).

Please include:

- the Mopster and macOS versions;
- a description of the problem and its impact;
- the steps to reproduce it, or a proof of concept;
- whether the problem is already public.

Mopster is maintained on a volunteer basis. You can expect an acknowledgement within 7 days and an assessment within 30 days. You will be kept informed, credited in the release notes if you wish, and consulted on the disclosure date once a fix is available.

## Scope

In scope, for example:

- a way to make Mopster remove or modify something outside what the user saw and selected, including a path that gets past `SafetyGuard` (protected folders, secret stores, symlink or race tricks, Mopster's own bundle);
- Mopster emptying the Trash;
- a maintenance task or helper running a command outside the reviewed allowlist, or arguments from a file name being interpreted as code (shell, AppleScript, `launchctl`);
- any network request other than the update checks described in the README;
- data from the Mac leaving it.

Out of scope:

- attacks that require an already compromised user account or administrator access;
- the Gatekeeper warning shown on first launch of builds that are not notarized;
- Mopster not detecting malware: it is not an antivirus (see the FAQ in the README).

## Distribution

Release builds are signed **ad hoc** and are not notarized. Verify a download against the `SHA256SUMS` file published with each release (`shasum -a 256 -c SHA256SUMS`).

Developer ID signing and notarization, and a Mac App Store build, are on the [roadmap](README.md#roadmap).
