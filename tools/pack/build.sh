#!/bin/bash
# Build the app-ready Quran packs from this engine's JSON.
#
#   tools/pack/build.sh [path-to-Al-Islam-iOS]
#
# Default target is ../Al-Islam-iOS, i.e. the app checked out beside this repo. Writes:
#
#   <app>/Resources/JSONs/Quran/quran.qpk        114 surahs · 6,236 ayahs
#   <app>/Resources/JSONs/Quran/qiraat.qpk       7 riwayat
#   <app>/Resources/JSONs/Quran/surahinfos.qpk   "about this surah" prose
#   <app>/Resources/JSONs/Quran/manifest.json    what was built: shapes, sizes, sha256 each
#
# The JSON in data/ stays canonical and portable; these packs are a reproducible build
# artifact. Nothing is in a pack that is not in the JSON.
#
# Source of truth for the pack input is the APP's Resources/JSONs, because that is what the
# app actually ships today and the engine's data/ is extracted from it. They are verified
# identical in content; if they ever diverge, the app copy wins and data/ should be re-extracted.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
app="${1:-$(cd "$repo/.." && pwd)/Al-Islam-iOS}"

if [ ! -d "$app/Resources/JSONs" ]; then
    echo "error: no app at $app (pass its path as the first argument)" >&2
    exit 1
fi

out="$app/Resources/JSONs/Quran"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

echo "==> compiling the packer"
swiftc -O -parse-as-library "$here/pack-quran.swift" -o "$build/pack-quran"

echo "==> packing $app/Resources/JSONs -> $out"
mkdir -p "$out"
"$build/pack-quran" "$app/Resources/JSONs" "$out"

echo "==> done"
ls -la "$out"
