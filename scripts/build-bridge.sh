#!/bin/zsh
# Rebuild the prebuilt bridge (ios/dist/lib/libViroReact.a) from current
# sources and stamp it for the prepack freshness gate.
set -e
cd "$(dirname "$0")/../ios"
cp Podfile.lock Pods/Manifest.lock 2>/dev/null || true
xcodebuild -workspace ViroReact.xcworkspace -scheme Pods-ViroReact -sdk iphoneos \
  -configuration Release SYMROOT="$PWD/build" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ViroReact.xcodeproj -target ViroReact -sdk iphoneos \
  -configuration Release SYMROOT="$PWD/build" CODE_SIGNING_ALLOWED=NO build
cd ..
node -e "const{bridgeSourceHash}=require('./scripts/bridge-hash');require('fs').writeFileSync('ios/dist/lib/.source-hash',bridgeSourceHash(process.cwd()))"
echo "bridge rebuilt + stamped: $(ls -la ios/dist/lib/libViroReact.a | awk '{print $5, $6, $7, $8}')"
