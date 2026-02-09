#!/bin/bash
set -e

cd "$(dirname "$0")"

# MLX requires xcodebuild to compile Metal shaders
# swift build doesn't compile .metal files

# Build using xcodebuild (compiles Metal shaders)
if [ ! -f "Secrets.xcconfig" ]; then
    echo "Warning: Secrets.xcconfig not found. Google OAuth will not work."
    echo "Copy Secrets.xcconfig.example to Secrets.xcconfig and fill in the values."
fi

echo "Building with xcodebuild..."
xcodebuild \
    -scheme Gophy \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    build 2>&1 | grep -E "(error:|warning:|\*\* BUILD)" | tail -20

echo "Build completed, creating app bundle..."

# Create app bundle structure
APP_DIR=".build/debug/Gophy.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy main executable
cp .build/xcode/Build/Products/Debug/Gophy "$APP_DIR/Contents/MacOS/"

# Copy Info.plist and substitute secrets from xcconfig
cp Sources/Gophy/Info.plist "$APP_DIR/Contents/"
if [ -f "Secrets.xcconfig" ]; then
    _client_id=$(grep '^GOOGLE_CLIENT_ID' Secrets.xcconfig | head -1 | cut -d'=' -f2- | xargs)
    _client_secret=$(grep '^GOOGLE_CLIENT_SECRET' Secrets.xcconfig | head -1 | cut -d'=' -f2- | xargs)
    if [ -n "$_client_id" ]; then
        plutil -replace GoogleClientID -string "$_client_id" "$APP_DIR/Contents/Info.plist"
    fi
    if [ -n "$_client_secret" ]; then
        plutil -replace GoogleClientSecret -string "$_client_secret" "$APP_DIR/Contents/Info.plist"
    fi
fi

# Copy app icon
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
fi

# Copy MLX Metal library bundle (CRITICAL for Metal shader support)
if [ -d ".build/xcode/Build/Products/Debug/mlx-swift_Cmlx.bundle" ]; then
    cp -R ".build/xcode/Build/Products/Debug/mlx-swift_Cmlx.bundle" "$APP_DIR/Contents/Resources/"
    echo "Copied MLX Metal library bundle"
fi

# Sign the app
codesign --force --deep --sign - "$APP_DIR"

echo "Build complete: $APP_DIR"
