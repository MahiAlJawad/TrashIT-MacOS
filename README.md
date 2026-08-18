# TrashIT

TrashIT is an independently developed, native SwiftUI macOS storage advisor and cleaner. A scan starts with **zero selected items**. Typed recommendations and explicit Smart Selections help the user choose; visibility filters never alter selection.

TrashIT does not copy cleanup rules, code, strings, tests, or architecture from Mole or another cleaner. Rule provenance and safety constraints live in [docs/CLEANUP_RULES.md](docs/CLEANUP_RULES.md).

## Build and test

The package exposes a shared core, direct GUI, and free CLI scaffold:

```sh
swift test
swift run TrashITDirect
swift run trashit --version
```

The Xcode project contains two macOS products:

- `TrashITDirect`: full Developer ID/notarization candidate with the supported developer and system scanners.
- `TrashITAppStore`: sandboxed feasibility target limited to security-scoped, user-selected folders.

The App Store build intentionally has fewer capabilities. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Implemented safety model

- Safe cleanup, Older simulator runtimes, and Duplicate copies are explicit selection-replacing actions.
- The newest installed simulator minor/patch is retained for each platform and OS major; unknown, booted, active, and newest runtimes are never recommended.
- Duplicate copies require equal logical size and a streaming SHA-256 match, and are reverified immediately before cleanup.
- Package-manager caches prefer fixed, allowlisted owner commands; pnpm uses `store prune`, Maven/Dart remain manual review, and Homebrew targets downloads only.
- Project artifacts require an ecosystem manifest/config marker.
- Browser rules target exact cache leaves and exclude profiles and personal data.
- Persistent “Never suggest this” exclusions cover a path and its descendants.
- Ordinary filesystem cleanup moves items to Bin; permanent deletion is reserved for items already in Bin.
- Cleanup revalidates paths, symlinks, owner processes, duplicate hashes, and simulator inventory; changed state fails closed and is recorded.

## Licensing and contributions

Repository source and public builds are licensed under [GPL-3.0-or-later](LICENSE). Separate commercial licenses may be offered for paid signed GUI builds; see [COMMERCIAL-LICENSING.md](COMMERCIAL-LICENSING.md). GPL recipients may redistribute GPL builds and source.

The TrashIT name/logo are covered separately by [TRADEMARKS.md](TRADEMARKS.md). Outside code contributions remain paused until an open-source/IP lawyer approves the [CLA](CLA.md) and commercial distribution documents. See [CONTRIBUTING.md](CONTRIBUTING.md) and [THIRD_PARTY.md](THIRD_PARTY.md).
