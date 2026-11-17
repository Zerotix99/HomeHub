#!/usr/bin/env bash
set -e
echo "=== Building HomeHub.ipa locally on macOS ==="
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Installing xcodegen via Homebrew..."
    brew install xcodegen
fi
xcodegen generate
xcodebuild \
  -project HomeHub.xcodeproj \
  -scheme HomeHub \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

rm -rf dist HomeHub.ipa
mkdir -p dist/Payload
cp -R build/Build/Products/Release-iphoneos/HomeHub.app dist/Payload/
(cd dist && zip -qry ../HomeHub.ipa Payload)
echo "✅ Fertig! HomeHub.ipa erstellt:"
ls -lh HomeHub.ipa
