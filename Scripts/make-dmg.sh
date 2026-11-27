#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
output=${1:-dist}
output=${output:A}
bundle="$output/time_.app"
codesign --verify --deep --strict "$bundle"

mkdir -p .build
stage=$(mktemp -d "$PWD/.build/disk-image.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/volume"
ditto --noextattr --norsrc "$bundle" "$stage/volume/time_.app"
ln -s /Applications "$stage/volume/Applications"

archive=time_-macOS-arm64.dmg
hdiutil create -quiet -srcfolder "$stage/volume" -volname time_ -fs APFS -format UDZO "$stage/$archive"
codesign --sign - --timestamp=none --identifier software.rhythm.mac.diskimage "$stage/$archive"
codesign --verify "$stage/$archive"
hdiutil verify -quiet "$stage/$archive"

mv "$stage/$archive" "$output/$archive"
(cd "$output" && shasum -a 256 "$archive" > "$archive.sha256")
print "Built $output/$archive"
