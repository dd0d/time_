#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
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
swift -module-cache-path "$PWD/.build/module-cache" Scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier software.rhythm.mac --options runtime --timestamp=none "$bundle"
codesign --verify --deep --strict "$bundle"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$PWD/dist/time_-macOS-arm64.zip"
(cd dist && shasum -a 256 time_-macOS-arm64.zip > time_-macOS-arm64.zip.sha256)
print "Built $bundle"
