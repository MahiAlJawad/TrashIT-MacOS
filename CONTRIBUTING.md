# Contributing to TrashIT

Outside contributions are paused until the CLA and commercial licensing documents receive legal review. Issues, reproducible observations, and links to vendor documentation are welcome in the meantime.

Once contribution intake opens, every contributor must sign [CLA.md](CLA.md). A pull request must:

- be original work and use `GPL-3.0-or-later` SPDX headers;
- avoid copying source, cleanup tables, commands, strings, comments, tests, or architecture from Mole or another cleaner;
- document cleanup knowledge in [docs/CLEANUP_RULES.md](docs/CLEANUP_RULES.md), including source, regeneration, exclusions, blocking processes, owner command, and execution validation;
- add focused tests for positive, negative, changed-state, symlink, permission, and timeout behavior;
- update [THIRD_PARTY.md](THIRD_PARTY.md) for every dependency or incorporated data source; and
- pass `swift test`, both macOS app builds, the license checks, and `git diff --check`.

Do not commit private data, cleanup output, local filesystem inventories, signing identities, receipts, or App Store credentials.
