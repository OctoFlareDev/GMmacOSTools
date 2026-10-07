#!/bin/bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${GM_MAC_BUILD_DIR:-$(mktemp -d "${TMPDIR:-/tmp/}gmmacostools-build.XXXXXX")}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$BUILD_ROOT"
xcrun clang++ -std=c++17 -Wall -Wextra -Werror \
    "$SOURCE_ROOT/tests/MouseInputQueueTests.cpp" -o "$BUILD_ROOT/mouse-input-tests"
"$BUILD_ROOT/mouse-input-tests"
for BUILD_ARCH in arm64 x86_64; do
    xcrun clang++ -std=c++17 -fobjc-arc -dynamiclib -arch "$BUILD_ARCH" \
        -mmacosx-version-min=12.0 -framework Cocoa -framework Foundation -framework Security \
        "$SOURCE_ROOT/GMmacOSTools/GMmacOSTools.mm" \
        "$SOURCE_ROOT/GMmacOSTools/MouseInput.mm" \
        -install_name @rpath/libGMmacOSTools.dylib \
        -o "$BUILD_ROOT/libGMmacOSTools-$BUILD_ARCH.dylib"
done
xcrun lipo -create "$BUILD_ROOT/libGMmacOSTools-arm64.dylib" \
    "$BUILD_ROOT/libGMmacOSTools-x86_64.dylib" -output "$BUILD_ROOT/libGMmacOSTools.dylib"
codesign --force --sign - "$BUILD_ROOT/libGMmacOSTools.dylib"
codesign --verify --strict "$BUILD_ROOT/libGMmacOSTools.dylib"
printf 'Built: %s\n' "$BUILD_ROOT/libGMmacOSTools.dylib"
