# Distribution architecture

## Products

- `TrashITCore` is the Swift package library containing models, scanning, safety policy, cleanup planning/execution, persistence, and the shared SwiftUI surface.
- `TrashITDirect` is the full, non-sandboxed macOS application target intended for Developer ID signing and notarization.
- `TrashITAppStore` is a separate Xcode application target with App Sandbox and user-selected read/write entitlements.
- `trashit` is the free GPL CLI frontend over the same scanner, Smart Selection, cleanup engine, safety policy, revalidation, and receipt store as the direct GUI. It provides scan, cleanup preview/execution, JSON output, and history commands. Cleanup requires a typed Smart Selection and explicit `--yes` confirmation.

The App Store target compiles with `TRASHIT_APP_STORE`. It restores security-scoped bookmarks and only schedules project/old-file scanners for folders the user explicitly selects. Simulator, Docker, developer-tool, home-cache, Trash, backup, and external-command actions are omitted from its scanner set and rejected by policy if somehow presented.

## Feasibility gate

The sandboxed build compiling is not proof of App Review eligibility or useful feature parity. Before announcing it, test access across relaunch for selected folders, Downloads, browser caches, CoreSimulator, `simctl`, Docker, Finder Trash, cloud eviction, and receipts. Record every denial. Do not request temporary exceptions or root escalation; ship the Store edition only if user-selected project cleanup is valuable on its own.

## Release requirements

1. Run the test and license workflow.
2. Build `TrashITDirect`, `TrashITAppStore`, and `trashit` independently.
3. Review the complete dependency graph for dual-license compatibility.
4. Sign/notarize only from a clean tagged commit.
5. Attach or retain reproducible corresponding source for every GPL binary.
6. Supply counsel-approved commercial/EULA terms only with commercial builds.
7. Never place purchase validation in the GPL build configuration.
