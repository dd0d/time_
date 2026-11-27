#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
identity=${TIME_CODESIGN_IDENTITY:--}
if [[ "$identity" != - && -z "${TIME_NOTARY_PROFILE:-}" ]]; then
    print -u2 "Set TIME_NOTARY_PROFILE to notarize a Developer ID build."
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p .build/module-cache .build/cache .build/config .build/security

swift build -c release --product Rhythm --disable-sandbox \
    --cache-path .build/cache --config-path .build/config --security-path .build/security \
    -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"

if [[ "$(lipo -archs .build/release/Rhythm)" != arm64 ]]; then
    print -u2 "Building a time_ release requires Apple Silicon (arm64)."
    exit 1
fi

bundle="$PWD/dist/time_.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/release/Rhythm "$bundle/Contents/MacOS/time_"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp LICENSE "$bundle/Contents/Resources/LICENSE.txt"
for language in en ru; do
    ditto "Resources/$language.lproj" "$bundle/Contents/Resources/$language.lproj"
done
swift -module-cache-path "$PWD/.build/module-cache" Scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$bundle/Contents/Resources/AppIcon.icns"
archive="$PWD/dist/time_-macOS-arm64.zip"
if [[ "$identity" == - ]]; then
    codesign --force --sign - --identifier software.rhythm.mac --options runtime --timestamp=none "$bundle"
else
    codesign --force --sign "$identity" --identifier software.rhythm.mac --options runtime --timestamp "$bundle"
    submission=$(mktemp -d "$PWD/.build/notary.XXXXXX")
    trap 'rm -rf -- "$submission"' EXIT
    ditto -c -k --sequesterRsrc --keepParent "$bundle" "$submission/time_.zip"
    xcrun notarytool submit "$submission/time_.zip" --keychain-profile "$TIME_NOTARY_PROFILE" --wait
    xcrun stapler staple "$bundle"
    xcrun stapler validate "$bundle"
fi
codesign --verify --deep --strict "$bundle"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$archive"
(cd dist && shasum -a 256 time_-macOS-arm64.zip > time_-macOS-arm64.zip.sha256)
print "Built $bundle"
