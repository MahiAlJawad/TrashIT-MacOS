# TrashIT

TrashIT is a native SwiftUI macOS storage advisor and cleaner. It finds regeneratable developer artifacts, old downloads, large unused files, app caches, logs, backups, Trash contents, and cautiously identified application leftovers.

The app deliberately does not perform screenshot OCR or screenshot classification yet.

## Run

Open `Package.swift` in Xcode and run the `TrashIT` executable, or use:

```sh
swift run TrashIT
```

The command-line-tools-only environment can build and test the package, but running the graphical app requires a logged-in macOS desktop session.

## Safety principles

- All ordinary filesystem items—including caches and regeneratable developer data—are moved to Bin through Finder semantics.
- Permanent deletion is reserved for items that are already inside Bin and is labeled explicitly.
- Simulator changes use `xcrun simctl` rather than editing CoreSimulator internals.
- Symbolic links and protected system locations are rejected by the cleanup engine.
- Archives, backups, application leftovers, and unknown caches are never preselected.
- Every cleanup shows an immediate per-item result and produces a local receipt.

## Current scope

- Xcode Derived Data, test results, device support, documentation, simulator caches, devices, and runtimes.
- Homebrew, SwiftPM, CocoaPods, npm, Yarn, pnpm, Gradle, Maven, Flutter/Dart, and JetBrains caches.
- Generated project folders such as `node_modules`, `.build`, `.next`, `.dart_tool`, Pods, Carthage builds, and coverage output.
- Docker-reported reclaimable images, build cache, stopped containers, and networks through Docker's native prune command; volumes are retained.
- Large or old files in user-selected scan folders, plus installer/archive detection and likely duplicate downloads.
- General application caches, old logs and diagnostic reports.
- Local iCloud-copy eviction when the item reports that it is safely uploaded.
- iOS device-backup review, Trash review, and conservative app-leftover suggestions.
- Risk labels, target-based selection, actual volume capacity, cleanup results and receipts, and folder permissions.

TrashIT cannot promise that clearing a cache has zero effect: regeneratable items can still require a rebuild, reindex, or re-download. The interface explains this cost before cleanup.
