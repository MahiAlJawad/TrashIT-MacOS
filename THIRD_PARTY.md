# Dependencies and knowledge provenance

## Linked software

TrashIT currently has no third-party package dependency. It links only Apple SDK frameworks supplied with macOS/Xcode, including Foundation, AppKit, SwiftUI, and CryptoKit. Apple SDK components are not relicensed by this repository.

New dependencies require a recorded version, source URL, copyright holder, SPDX license, commercial-target compatibility decision, and license-text location. GPL-only dependencies must not enter shared code used by commercially licensed builds without a separate permission from their copyright holder.

## Cleanup knowledge

Cleanup behavior is implemented from vendor documentation, macOS APIs, native tool JSON/output, and original local fixtures. Product comparison may identify an area worth researching but is not accepted as implementation provenance. The detailed rule register is [docs/CLEANUP_RULES.md](docs/CLEANUP_RULES.md).

No Mole source, cleanup table, path list, regular expression, shell command, string, comment, test, or architecture has been incorporated.
