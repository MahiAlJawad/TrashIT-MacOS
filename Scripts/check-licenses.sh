#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

test -f LICENSE
grep -q "GNU GENERAL PUBLIC LICENSE" LICENSE
grep -q "Version 3, 29 June 2007" LICENSE

missing=0
for source_file in Package.swift $(find Sources Tests -name '*.swift' -type f | sort); do
    if ! grep -q "SPDX-License-Identifier: GPL-3.0-or-later" "$source_file"; then
        echo "Missing GPL SPDX header: $source_file" >&2
        missing=1
    fi
done
test "$missing" -eq 0

if grep -RniE "tw93|github\.com/tw93|copyright.*mole" Sources Tests; then
    echo "Possible copied project notice/reference found in source or tests." >&2
    exit 1
fi

if test -f Package.resolved; then
    echo "Swift package dependencies require an explicit THIRD_PARTY.md license review." >&2
    exit 1
fi

if test -n "${GITHUB_ACTOR:-}" && test "${GITHUB_ACTOR}" != "MahiAlJawad"; then
    if ! grep -Fxq "${GITHUB_ACTOR}" .github/cla-signers.txt; then
        echo "${GITHUB_ACTOR} is not recorded as having signed the lawyer-approved CLA." >&2
        exit 1
    fi
fi
