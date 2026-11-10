#!/bin/sh
# Packs build/InkPad.app into InkPad-<version>.dmg (drag-to-Applications layout). Run scripts/bundle.sh first.
set -e
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
OUT="InkPad-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/InkPad.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "InkPad" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
echo "Built $OUT"
