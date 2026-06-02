#!/bin/sh

set -o pipefail

cd "$(dirname "$0")"
cd ../

MAILCORE_DIR="`pwd`"
BUILD_DIR="$MAILCORE_DIR/.build"
LOGS_DIR="$MAILCORE_DIR/logs"
FRAMEWORK_NAME="MailCore2.xcframework"

mkdir -p $BUILD_DIR
mkdir -p $LOGS_DIR

LOG_FILE="build-$(date +%Y%m%d-%H%M%S).log"
LOG_PATH="$LOGS_DIR/$LOG_FILE"

rm -rf "$BUILD_DIR/$FRAMEWORK_NAME"

cd build-mac

# Build Mac Archive
xcodebuild archive -scheme "mailcore osx" \
    -arch "x86_64" \
    -archivePath "$BUILD_DIR/mailcore2.macOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES 2>&1 | tee -a "$LOG_PATH"
    
# Build iOS Archive
xcodebuild archive -scheme "mailcore ios" \
    -destination "generic/platform=iOS" \
    -archivePath "$BUILD_DIR/mailcore2.iOS.xcarchive" \
    -sdk iphoneos \
    ARCHS="arm64" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES 2>&1 | tee -a "$LOG_PATH"

# Build iOS Simulator Archive
xcodebuild archive -scheme "mailcore ios" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "$BUILD_DIR/mailcore2.iOS-Simulator.xcarchive" \
    -sdk iphonesimulator \
    ARCHS="x86_64 arm64" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES 2>&1 | tee -a "$LOG_PATH"

# Build Mac Catalyst Archive - UNCOMMENT ONCE MAC CATALYST BUILDING IS FIXED
#xcodebuild archive -scheme "mailcore ios" \
#    -destination "platform=macOS,variant=Mac Catalyst" \
#    -archivePath "$BUILD_DIR/mailcore2.macOS-Catalyst.xcarchive" \
#    -sdk ???? \
#    SKIP_INSTALL=NO \
#    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

cd $BUILD_DIR

# Create Combined XCArchive - REMOVE ONCE MAC CATALYST BUILDING IS FIXED
xcodebuild -create-xcframework \
	-framework "mailcore2.macOS.xcarchive/Products/Frameworks/MailCore.framework" \
	-framework "mailcore2.iOS-Simulator.xcarchive/Products/Frameworks/MailCore.framework" \
	-framework "mailcore2.iOS.xcarchive/Products/Frameworks/MailCore.framework" \
	-output "$FRAMEWORK_NAME" 2>&1 | tee -a "$LOG_PATH"

# Create Combine XCArchive - UNCOMMENT ONCE MAC CATALYST BUILDING IS FIXED
# xcodebuild -create-xcframework \
# 	-framework "$BUILD_DIR/mailcore2.macOS.xcarchive/Products/Library/Frameworks/MailCore.framework" \
# 	-framework "$BUILD_DIR/mailcore2.iOS-Simulator.xcarchive/Products/Library/Frameworks/MailCore.framework" \
# 	-framework "$BUILD_DIR/mailcore2.iOS.xcarchive/Products/Library/Frameworks/MailCore.framework" \
# 	-framework "$BUILD_DIR/mailcore2.macOS-Catalyst.xcarchive/Products/Library/Frameworks/MailCore.framework"
# 	-output "$BUILD_DIR/mailcore2.xcframework"

# Clean Up
rm -rf "$BUILD_DIR/mailcore2.macOS.xcarchive"
rm -rf "$BUILD_DIR/mailcore2.iOS-Simulator.xcarchive"
rm -rf "$BUILD_DIR/mailcore2.iOS.xcarchive"
