# Cleanup rule register

Every new rule must fill all six fields: disposable reason, regeneration path, exclusions, blockers, preferred owner action, and execution-time validation. Paths below are original TrashIT rules derived from vendor documentation or local tool output.

## Xcode and CoreSimulator

- **Leaves:** children of `~/Library/Developer/Xcode/{DerivedData,Products,DocumentationCache,iOS DeviceSupport,watchOS DeviceSupport}` and `~/Library/Developer/CoreSimulator/Caches`.
- **Why/regeneration:** build/index products and simulator caches are rebuilt; documentation/device support can be downloaded or recreated by Xcode.
- **Never remove:** `Archives` automatically, project sources, signing assets, or Xcode preferences. Archives are manual, potentially irreplaceable review items.
- **Blockers:** Xcode blocks execution. The engine revalidates the location and rejects symlinks/protected paths before moving items to Bin.
- **Provenance:** Xcode-generated directory observation and `xcrun simctl` JSON/output, with original fixtures.

## Simulator runtimes

- Runtime inventory and deletion identifiers come from `xcrun simctl runtime list -v -j`; device state comes from `xcrun simctl list -j`.
- TrashIT groups semantic versions by platform and OS major, keeps the newest minor/patch/build, and recommends older ready versions only. Unknown, newest, non-deletable, booted, or in-use runtimes are not recommended.
- Immediately before deletion, the runtime inventory and booted-device mapping are read again. A changed recommendation fails closed and is recorded.

## Package and language tools

| Tool | Bounded observed leaf | Owner action | Exclusions and blockers |
|---|---|---|---|
| Homebrew | `~/Library/Caches/Homebrew/downloads` | Move downloads to Bin | Never cellar, formula metadata, or installed packages; block `brew`. |
| npm | `~/.npm/_cacache` | `npm cache clean --force` | Never projects, global packages, config, or credentials; block npm/node. |
| pnpm | `~/Library/pnpm/store` | `pnpm store prune` | Owner decides what is unreferenced; never delete the store directly; block pnpm/node. |
| pip | `~/Library/Caches/pip` | `pip cache purge` | Never environments or indexes/config; block pip/Python. |
| uv | `~/.cache/uv` | `uv cache prune` | Never project `.venv` through this global rule; block uv. |
| Go | standard build/module cache leaves | `go clean -cache` or `go clean -modcache` | Never source, installed binaries, or `go.mod`; block go. |
| Bun | `~/.bun/install/cache` | `bun pm cache rm` | Never project dependencies/config; block bun. |
| Corepack | `~/.cache/node/corepack` | `corepack cache clean` | Never project lockfiles; block corepack/node. |
| Rustup | `~/.rustup/{downloads,tmp}` | bounded move to Bin | Never installed toolchains; block rustup. |
| Cargo | `~/.cargo/registry/cache` | manual review | Never installed commands, source worktrees, credentials, or config; block cargo. |
| Android | `~/.android/cache` | bounded move to Bin | Never SDK installations, AVDs, signing keys, or projects; block Studio/sdkmanager. |
| Maven/Pub | shared stores | manual review only | Local-only Maven artifacts and unpublished/path Pub state may not be recoverable. |

Owner-command documentation: [npm cache](https://docs.npmjs.com/cli/commands/npm-cache), [pnpm store](https://pnpm.io/cli/store), [pip cache](https://pip.pypa.io/en/stable/cli/pip_cache/), [uv cache](https://docs.astral.sh/uv/concepts/cache/), [Go clean/module cache](https://go.dev/ref/mod), [Bun cache](https://bun.com/docs/pm/cli/pm), and [Corepack cache](https://github.com/nodejs/corepack#utility-commands).

## Project artifacts

Generated folder names are accepted only when an owning manifest/config is found within the bounded ancestor search. Implemented pairs cover Swift (`Package.swift`), Rust (`Cargo.toml`), Maven (`pom.xml`), Python manifests, JavaScript `package.json`, Next/Nuxt/Turbo/Parcel configs, Zig `build.zig`, Angular, Svelte, Astro, React Native/Expo-compatible project markers, Dart `pubspec.yaml`, CocoaPods `Podfile`, Xcode project metadata, and Carthage manifests. Symlinks/packages are not traversed, scans have depth/item/time limits, and every path is revalidated before cleanup.

## Verified duplicates

Only same-folder names ending in `(n)`, `copy`, or `copy n` are candidates. The unnumbered sibling must exist as a regular non-symlink file, logical sizes must match, and streaming SHA-256 digests must be equal. Both files are rehashed immediately before moving only the copy to Bin. Missing, changed, unreadable, timed-out, or same-size-different-content files fail closed.

## Browser caches

Exact cache-container leaves are used for Safari, Chrome, Chromium, Edge, Firefox, and Arc under `~/Library/Caches`. Profile roots are never scanned. Cookies, sessions, credentials, bookmarks, extensions, downloads, and documents are outside every target. The owning browser must be closed and bundle state is checked at execution.

## Other review-only data

Trash contents, local device backups, archives/installers, old large files, generic cloud copies, Docker reclaimable data, and Xcode archives require explicit review unless a separately typed recommendation is present. Broad application-cache catalogs, application uninstalling/leftovers, disk maps, optimization, privileged cleanup, and monitoring are intentionally not implemented.
