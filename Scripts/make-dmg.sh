#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
output=${1:-dist}
output=${output:A}
bundle="$output/time_.app"
identity=${TIME_CODESIGN_IDENTITY:--}
if [[ "$identity" != - && -z "${TIME_NOTARY_PROFILE:-}" ]]; then
    print -u2 "Set TIME_NOTARY_PROFILE to notarize a Developer ID disk image."
    exit 1
fi
codesign --verify --deep --strict "$bundle"
if [[ "$identity" != - ]]; then
    xcrun stapler validate "$bundle"
fi

mkdir -p .build
stage=$(mktemp -d "$PWD/.build/disk-image.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/volume"
ditto "$bundle" "$stage/volume/time_.app"
ln -s /Applications "$stage/volume/Applications"

archive=time_-macOS-arm64.dmg
hdiutil makehybrid -quiet -hfs -hfs-volume-name time_ -o "$stage/volume.dmg" "$stage/volume"
hdiutil convert -quiet "$stage/volume.dmg" -format UDZO -o "$stage/$archive"
if [[ "$identity" == - ]]; then
    codesign --sign - --timestamp=none --identifier software.rhythm.mac.diskimage "$stage/$archive"
else
    codesign --sign "$identity" --timestamp --identifier software.rhythm.mac.diskimage "$stage/$archive"
    xcrun notarytool submit "$stage/$archive" --keychain-profile "$TIME_NOTARY_PROFILE" --wait
    xcrun stapler staple "$stage/$archive"
    xcrun stapler validate "$stage/$archive"
fi
codesign --verify "$stage/$archive"
hdiutil verify -quiet "$stage/$archive"

mv "$stage/$archive" "$output/$archive"
(cd "$output" && shasum -a 256 "$archive" > "$archive.sha256")
print "Built $output/$archive"
