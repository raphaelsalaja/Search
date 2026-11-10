#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out=$(mktemp -d "${TMPDIR:-/tmp}/search-domain-groups.XXXXXX")
trap 'rm -rf "$out"' EXIT HUP INT TERM
swiftc -swift-version 5 \
    "$repo_root/Sources/Search/Registrable.swift" \
    "$repo_root/Sources/Search/TabGroup.swift" \
    "$repo_root/Sources/Search/DomainGroups.swift" \
    "$repo_root/Tests/DomainGroupRegression/main.swift" \
    -o "$out/domain-groups"
"$out/domain-groups"
