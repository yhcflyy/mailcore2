#!/bin/sh
# Build MailCore.xcframework from local deps/* and this repo's build-mac project.
set -e

pushd "`dirname "$0"`" > /dev/null
scriptpath="`pwd`"
popd > /dev/null

. "$scriptpath/include.sh/build-dep.sh"

MAILCORE_ROOT="$scriptpath/.."
OUTPUT_XCFRAMEWORK="$MAILCORE_ROOT/MailCore.xcframework"
BUILD_SYMROOT="$MAILCORE_ROOT/.build/mailcore-ios"
SDK_IOS_VERSION="`xcodebuild -showsdks 2>/dev/null | grep iphoneos | head -n 1 | sed 's/.*iphoneos\(.*\)/\1/'`"

echo "==> [1/4] Building iOS dependencies from deps/* into Externals/ ..."
build_for_external=1 "$scriptpath/build-ctemplate-ios.sh"
build_for_external=1 "$scriptpath/build-libetpan-ios.sh"
build_for_external=1 "$scriptpath/build-tidy-ios.sh"

for _dep in ctemplate-ios libetpan-ios tidy-html5-ios libsasl-ios ; do
  if test ! -d "$MAILCORE_ROOT/Externals/$_dep" ; then
    echo "ERROR: Externals/$_dep is missing after dependency build"
    exit 1
  fi
done
fix_tidy_include_layout "$MAILCORE_ROOT/Externals/tidy-html5-ios" "$MAILCORE_ROOT/deps/tidy-html5"
echo "    Dependencies OK"

echo "==> [2/4] Building MailCore.framework (iphoneos) ..."
rm -rf "$BUILD_SYMROOT" "$OUTPUT_XCFRAMEWORK"
mkdir -p "$BUILD_SYMROOT"

cd "$MAILCORE_ROOT/build-mac"
xcodebuild -project mailcore2.xcodeproj \
  -scheme "mailcore ios" \
  -configuration Release \
  -sdk "iphoneos$SDK_IOS_VERSION" \
  ARCHS=arm64 \
  IPHONEOS_DEPLOYMENT_TARGET=12.0 \
  SYMROOT="$BUILD_SYMROOT" \
  OBJROOT="$BUILD_SYMROOT/obj/iphoneos" \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ENABLE_BITCODE=NO \
  ONLY_ACTIVE_ARCH=NO

echo "==> [3/4] Building MailCore.framework (iphonesimulator) ..."
xcodebuild -project mailcore2.xcodeproj \
  -scheme "mailcore ios" \
  -configuration Release \
  -sdk "iphonesimulator$SDK_IOS_VERSION" \
  ARCHS="arm64 x86_64" \
  IPHONEOS_DEPLOYMENT_TARGET=12.0 \
  SYMROOT="$BUILD_SYMROOT" \
  OBJROOT="$BUILD_SYMROOT/obj/iphonesimulator" \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ENABLE_BITCODE=NO \
  ONLY_ACTIVE_ARCH=NO

_DEVICE_FW="$BUILD_SYMROOT/Release-iphoneos/MailCore.framework"
_SIM_FW="$BUILD_SYMROOT/Release-iphonesimulator/MailCore.framework"
if test ! -d "$_DEVICE_FW" ; then
  echo "ERROR: $_DEVICE_FW not found"
  ls -la "$BUILD_SYMROOT" 2>/dev/null || true
  ls -la "$BUILD_SYMROOT/Release-iphoneos" 2>/dev/null || true
  exit 1
fi
if test ! -d "$_SIM_FW" ; then
  echo "ERROR: $_SIM_FW not found"
  ls -la "$BUILD_SYMROOT/Release-iphonesimulator" 2>/dev/null || true
  exit 1
fi

echo "==> [4/4] Creating MailCore.xcframework ..."
xcodebuild -create-xcframework \
  -framework "$_DEVICE_FW" \
  -framework "$_SIM_FW" \
  -output "$OUTPUT_XCFRAMEWORK"

echo ""
echo "Done: $OUTPUT_XCFRAMEWORK"
ls -la "$OUTPUT_XCFRAMEWORK"
