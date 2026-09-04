#!/bin/zsh
# Release Pour: bump version, build, zip, tag, GitHub release, update the Homebrew cask.
# Usage: scripts/release.sh 0.1.2 ["release notes"]
set -euo pipefail
V=${1:?version}; NOTES=${2:-"Pour $V"}
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 1; }

BUILD=$(( $(grep -oE 'CFBundleVersion: "[0-9]+"' project.yml | grep -oE '[0-9]+') + 1 ))
sed -i '' -e "s/CFBundleShortVersionString: \"[0-9.]*\"/CFBundleShortVersionString: \"$V\"/" -e "s/CFBundleVersion: \"[0-9]*\"/CFBundleVersion: \"$BUILD\"/" project.yml
xcodegen generate >/dev/null
git commit -qam "release: $V" && git push -q origin main

xcodebuild -scheme Pour -configuration Release -derivedDataPath build build 2>&1 | grep -E 'error|BUILD'
ZIP=$(mktemp -d)/Pour-$V.zip
ditto -c -k --keepParent build/Build/Products/Release/Pour.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

git tag -a "v$V" -m "Pour $V" && git push -q origin "v$V"
gh release create "v$V" "$ZIP" --title "Pour $V" --notes "$NOTES"

TAP=$(mktemp -d); gh repo clone iammayron/homebrew-tap "$TAP" -- -q
sed -i '' -e "s/version \"[0-9.]*\"/version \"$V\"/" -e "s/sha256 \"[0-9a-f]*\"/sha256 \"$SHA\"/" "$TAP/Casks/pour.rb"
git -C "$TAP" commit -qam "pour $V" && git -C "$TAP" push -q
echo "released $V ($SHA)"
