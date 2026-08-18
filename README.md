# TrashIT

TrashIT is an independently developed, native SwiftUI macOS storage advisor and cleaner. A scan starts with **zero selected items**. Typed recommendations and explicit Smart Selections help the user choose; visibility filters never alter selection.

TrashIT does not copy cleanup rules, code, strings, tests, or architecture from Mole or another cleaner. Rule provenance and safety constraints live in [docs/CLEANUP_RULES.md](docs/CLEANUP_RULES.md).

## Build, run, and test

### Requirements

- macOS 14 or newer.
- Xcode 15.4 or newer. Xcode 16.4 is used by CI.
- Xcode Command Line Tools selected with `xcode-select`.

Verify the active toolchain:

```sh
xcode-select -p
xcodebuild -version
swift --version
```

If the first command does not point inside the intended Xcode installation, select it before continuing:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### 1. Get the source

```sh
git clone https://github.com/MahiAlJawad/TrashIT-MacOS.git
cd TrashIT-MacOS
```

### 2. Run the direct macOS application in Xcode

This is the recommended way to run the complete GUI application:

1. Open `TrashIT.xcodeproj` in Xcode.
2. Choose the `TrashITDirect` scheme in the toolbar.
3. Choose **My Mac** as the run destination.
4. Select **Product → Run**, or press <kbd>⌘R</kbd>.
5. Grant Full Disk Access only if you want to test locations macOS otherwise protects. TrashIT continues with partial access and reports skipped locations.

Open the project from Terminal with:

```sh
open TrashIT.xcodeproj
```

### 3. Build and launch the direct app entirely from Terminal

`swift run TrashITDirect` launches the Swift package executable, but it is not the canonical Xcode `.app` product used for signing and distribution. To build the actual application bundle:

```sh
xcodebuild \
  -project TrashIT.xcodeproj \
  -scheme TrashITDirect \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/xcode-direct \
  CODE_SIGNING_ALLOWED=NO \
  build

open .build/xcode-direct/Build/Products/Debug/TrashITDirect.app
```

For day-to-day package development, this shorter command remains available:

```sh
swift run TrashITDirect
```

### 4. Build and run the sandboxed App Store edition

In Xcode, select the `TrashITAppStore` scheme, choose **My Mac**, and press <kbd>⌘R</kbd>. From Terminal:

```sh
xcodebuild \
  -project TrashIT.xcodeproj \
  -scheme TrashITAppStore \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/xcode-app-store \
  CODE_SIGNING_ALLOWED=NO \
  build

open .build/xcode-app-store/Build/Products/Debug/TrashITAppStore.app
```

The App Store edition is intentionally narrower. It scans project artifacts, old files, and verified duplicates only inside folders the user explicitly grants. Simulator, Docker, developer-tool, browser-cache, Trash, backup, and external-command cleanup are excluded. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

### 5. Build and use the free CLI

The `trashit` executable is a functional GPL frontend over `TrashITCore`; it uses the same scanners, Smart Selections, safety policy, execution-time revalidation, cleanup engine, and receipt history as the direct GUI.

Build it and inspect the available commands:

```sh
swift build --product trashit
.build/debug/trashit --version
.build/debug/trashit help
```

Scan without selecting anything:

```sh
.build/debug/trashit scan
.build/debug/trashit scan ~/Projects/MyApp
```

A path adds a root for project-artifact, old-file, archive, cloud-copy, and duplicate discovery. It does not disable the direct edition's known Xcode, simulator, developer-cache, browser-cache, log, backup, or Trash scanners. Always preview a Smart Selection before cleanup.

Preview one of the GUI-equivalent Smart Selections. A leading `*` marks what that rule would clean:

```sh
.build/debug/trashit scan ~/Projects/MyApp --select safe
.build/debug/trashit scan --select simulators
.build/debug/trashit scan ~/Downloads --select duplicates
```

`clean` without `--yes` is also preview-only and returns exit status 2:

```sh
.build/debug/trashit clean ~/Projects/MyApp --select safe
```

After reviewing every selected path, repeat with explicit confirmation:

```sh
.build/debug/trashit clean ~/Projects/MyApp --select safe --yes
```

Other useful commands:

```sh
.build/debug/trashit history
.build/debug/trashit scan ~/Projects/MyApp --select safe --json
.build/debug/trashit scan --path ~/Projects/AppA --path ~/Projects/AppB --exclude ~/Projects/AppB/Keep
.build/debug/trashit scan ~/Downloads --old-days 365 --minimum-file-size 500MB
```

The CLI never cleans arbitrary scan results. Cleanup requires `safe`, `simulators`, or `duplicates`, then rescans and revalidates immediately before executing. Ordinary files move to Bin, and every attempt writes the same receipt format used by the GUI.

For a release-optimized binary:

```sh
swift build -c release --product trashit
.build/release/trashit help
```

### 6. Run tests and release checks

```sh
swift test
bash Scripts/check-licenses.sh
git diff --check
```

CI additionally builds `TrashITDirect`, `TrashITAppStore`, and `trashit` independently.

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
