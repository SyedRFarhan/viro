# ViroReact iOS Prebuild Guide

This document describes how to build the `libViroReact.a` static library for iOS and package it for use in a consuming application (e.g., an Expo app).

## Prerequisites

- **Xcode 15+** with iOS SDK 18.x
- **iOS 18.0+ minimum deployment target** (required for ARKit camera zoom APIs)
- **Node.js** (v18+ recommended, managed via nvm or similar)
- **CocoaPods** installed (`gem install cocoapods`)
- React Native 0.81+ with New Architecture enabled

## Directory Structure

```
viro/
├── ios/
│   ├── ViroReact/              # Objective-C/C++ source files
│   ├── ViroReact.podspec       # Podspec for CocoaPods
│   ├── ViroReact.xcworkspace   # Xcode workspace
│   ├── Podfile                 # Pods configuration for building
│   ├── .xcode.env.local        # Local Xcode environment (NODE_BINARY)
│   └── dist/
│       ├── lib/
│       │   └── libViroReact.a  # Prebuilt static library
│       ├── include/            # Public headers
│       └── ViroRenderer/       # ViroKit.framework
├── components/                 # TypeScript source
├── dist/                       # Compiled JS/TS output
└── package.json
```

## Quick Build (Recommended)

For routine builds after code changes, use the `after:release` script which handles everything:

```bash
cd viro

# If using nvm, source your shell config first
source ~/.zshrc  # or ~/.bashrc

# 1. Build the native library
cd ios
RCT_NEW_ARCH_ENABLED=1 \
REACT_NATIVE_PATH=$(pwd)/../node_modules/react-native \
xcodebuild \
  -workspace ViroReact.xcworkspace \
  -scheme ViroReact \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  build

# 2. Copy LATEST build to dist (IMPORTANT: verify timestamp!)
LATEST_LIB=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "libViroReact.a" -path "*ViroReact*Release-iphoneos*" \
  -print0 | xargs -0 ls -t | head -1)
cp "$LATEST_LIB" dist/lib/
ls -la dist/lib/libViroReact.a  # Verify timestamp is current!

# 3. Bump version and package
cd ..
# Edit package.json to bump version (e.g., 2.61.7 -> 2.61.8)
npm run after:release
```

The `after:release` script runs TypeScript compilation, tests, and creates the tarball.

> ⚠️ **Always verify the library timestamp!** DerivedData may contain old builds. If the timestamp doesn't match your build time, you're copying stale code.

---

## Full Setup (First Time)

### Step 1: Install Dependencies

```bash
cd viro
npm install

cd ios
pod install
```

## Step 2: Configure Node Binary Path

The Xcode build scripts require access to the Node.js binary. Create or update `.xcode.env.local`:

```bash
# viro/ios/.xcode.env.local
export NODE_BINARY=/path/to/your/node/binary
```

To find your Node binary path:
```bash
which node
# Example output: /Users/yourname/.nvm/versions/node/v22.14.0/bin/node
```

**Important:** This file contains a machine-specific path. For portability, you may need to update this on each development machine.

### Step 3: Build the Static Library

Run the following command from the `viro/ios` directory:

```bash
cd viro/ios

# IMPORTANT: If using nvm, source your shell config first!
source ~/.zshrc  # or ~/.bashrc

RCT_NEW_ARCH_ENABLED=1 \
REACT_NATIVE_PATH=$(pwd)/../node_modules/react-native \
xcodebuild \
  -workspace ViroReact.xcworkspace \
  -scheme ViroReact \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  build
```

**Note:** The `source ~/.zshrc` ensures nvm-managed Node.js is available to Xcode build scripts.

### Build Command Breakdown

| Parameter | Purpose |
|-----------|---------|
| `RCT_NEW_ARCH_ENABLED=1` | Enables React Native New Architecture (Fabric) |
| `REACT_NATIVE_PATH=...` | Points to React Native for Hermes scripts |
| `-configuration Release` | Builds optimized release version |
| `-sdk iphoneos` | Builds for physical iOS devices |
| `-destination 'generic/platform=iOS'` | Generic iOS destination |

### Step 4: Copy Built Library to dist

After a successful build, copy the library to the distribution folder.

**IMPORTANT:** DerivedData may contain multiple builds. Always verify you're copying the LATEST one!

```bash
# Find the NEWEST libViroReact.a (sorted by modification time)
LATEST_LIB=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "libViroReact.a" \
  -path "*ViroReact*Release-iphoneos*" \
  -print0 | xargs -0 ls -t | head -1)

echo "Latest build: $LATEST_LIB"
ls -la "$LATEST_LIB"

# Copy to dist
cp "$LATEST_LIB" dist/lib/

# Verify the copy timestamp matches
ls -la dist/lib/libViroReact.a
```

**Quick copy** (if you just ran the build and there's only one project):
```bash
cp ~/Library/Developer/Xcode/DerivedData/ViroReact-*/Build/Products/Release-iphoneos/libViroReact.a \
   dist/lib/
```

**Verify it's recent** - the timestamp should match your build time:
```bash
stat -f "%Sm" dist/lib/libViroReact.a
# Should show current date/time, e.g., "Jan 14 11:37:00 2025"
```

### Step 5: Verify the Library

Check that the library contains the expected symbols:

```bash
nm -g dist/lib/libViroReact.a | grep "ARSceneNavigator"
```

Expected output should include symbols like:
```
-[VRTARSceneNavigator getNativeARSession]
-[VRTARSceneNavigatorModule isNativeARSessionAvailable:resolve:reject:]
```

### Step 6: Build TypeScript

Compile the TypeScript components:

```bash
cd viro
npm run build
```

This generates the `dist/` folder with compiled JavaScript and type definitions.

### Step 7: Package for Local Use

**Recommended:** Use the `after:release` script which handles TypeScript build, tests, and packaging:

```bash
cd viro

# First, bump the version in package.json
# e.g., "version": "2.61.7" -> "version": "2.61.8"

# Then run the release script
npm run after:release
```

This creates `reactvision-react-viro-X.X.X.tgz` with all necessary files.

**Alternative:** Manual packaging (if you only need the tarball):
```bash
cd viro
npm run build  # Build TypeScript first
npm pack
```

## Using the Prebuilt Library in Another App

### Option A: Install from Tarball

```bash
cd your-expo-app
npm install ../path/to/viro/reactvision-react-viro-X.X.X.tgz
```

### Option B: Link Locally (Development)

In your app's `package.json`:
```json
{
  "dependencies": {
    "@reactvision/react-viro": "file:../path/to/viro"
  }
}
```

Then run:
```bash
npm install
cd ios && pod install
```

### Expo App Configuration

For Expo apps, ensure the plugin is configured in `app.json`:

```json
{
  "expo": {
    "plugins": ["@reactvision/react-viro"]
  }
}
```

Run prebuild and build:
```bash
npx expo prebuild --clean
npx expo run:ios --device
```

## Troubleshooting

### Stale Build (Code Changes Not Appearing)

**Symptom:** You made code changes but they don't appear in the app after rebuild.

**Cause:** DerivedData contains multiple builds; you may have copied an OLD build instead of the latest.

**Solution:** Always find and copy the NEWEST library:
```bash
# List all builds sorted by time (newest first)
find ~/Library/Developer/Xcode/DerivedData \
  -name "libViroReact.a" -path "*ViroReact*Release-iphoneos*" \
  -print0 | xargs -0 ls -lt

# Copy the newest one
LATEST_LIB=$(find ~/Library/Developer/Xcode/DerivedData \
  -name "libViroReact.a" -path "*ViroReact*Release-iphoneos*" \
  -print0 | xargs -0 ls -t | head -1)
cp "$LATEST_LIB" dist/lib/

# Verify timestamp matches your build time
ls -la dist/lib/libViroReact.a
```

**Prevention:** Clean DerivedData periodically:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/ViroReact-*
```

### Hermes Script Failure

**Error:** `[Hermes] Replace Hermes for the right configuration, if needed` fails

**Solution:** Ensure `REACT_NATIVE_PATH` is set when running xcodebuild:
```bash
REACT_NATIVE_PATH=$(pwd)/../node_modules/react-native xcodebuild ...
```

### Node Binary Not Found

**Error:** Build fails with "node: command not found"

**Solution 1:** Source your shell config before building (if using nvm):
```bash
source ~/.zshrc  # or ~/.bashrc
# Then run xcodebuild
```

**Solution 2:** Update `ios/.xcode.env.local` with the correct path:
```bash
export NODE_BINARY=$(which node)
# Then copy the output to .xcode.env.local as a hardcoded path
```

### Duplicate Symbols

**Error:** Linker errors about duplicate symbols during app build

**Solution:** Ensure `dist/lib/` only contains `libViroReact.a`. Remove any React Native dependency libraries:
```bash
find viro/ios/dist/lib -type f ! -name 'libViroReact.a' -delete
rm -rf viro/ios/dist/lib/*.bundle
```

### Metro TreeFS Error

**Error:** `TreeFS: Could not add directory node_modules/@reactvision/react-viro`

**Solution:** Clear Metro cache and watchman:
```bash
watchman watch-del-all
rm -rf $TMPDIR/metro-*
npx expo run:ios --device
```

## Files Included in NPM Package

The `files` array in `package.json` specifies what gets published:

```json
{
  "files": [
    "index.ts",
    "components",
    "dist",
    "ios/dist",
    "ios/ViroReact.podspec",
    "android/..."
  ]
}
```

**Note:** The `ios/ViroReact/` source files are NOT included when distributing the prebuilt library. The podspec is configured to use `vendored_libraries` when `dist/lib/libViroReact.a` exists.

## Podspec Conditional Logic

The `ViroReact.podspec` automatically detects the prebuilt library:

```ruby
lib_path = 'dist/lib/libViroReact.a'
has_prebuilt_lib = File.exist?(File.join(__dir__, lib_path))

if has_prebuilt_lib
  s.source_files = ['ViroReact/**/*.h', 'dist/include/**/*.h']
  s.vendored_libraries = lib_path
else
  s.source_files = ['ViroReact/**/*.{h,m,mm}']
end
```

## Complete Build Script

For convenience, here's a complete build script:

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "=== Installing dependencies ==="
npm install
cd ios && pod install && cd ..

echo "=== Building TypeScript ==="
npm run build

echo "=== Building iOS Static Library ==="
cd ios
RCT_NEW_ARCH_ENABLED=1 \
REACT_NATIVE_PATH=$(pwd)/../node_modules/react-native \
xcodebuild \
  -workspace ViroReact.xcworkspace \
  -scheme ViroReact \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  build

echo "=== Copying Library ==="
find ~/Library/Developer/Xcode/DerivedData \
  -name "libViroReact.a" \
  -path "*Release-iphoneos*" \
  -newer dist/lib/libViroReact.a 2>/dev/null \
  -exec cp {} dist/lib/ \; || \
find ~/Library/Developer/Xcode/DerivedData \
  -name "libViroReact.a" \
  -path "*Release-iphoneos*" \
  -exec cp {} dist/lib/ \;

echo "=== Cleaning dist/lib ==="
find dist/lib -type f ! -name 'libViroReact.a' -delete 2>/dev/null || true
rm -rf dist/lib/*.bundle 2>/dev/null || true

cd ..

echo "=== Creating NPM Package ==="
npm pack

echo "=== Done ==="
ls -la *.tgz
```

Save this as `scripts/build-ios.sh` and run with:
```bash
chmod +x scripts/build-ios.sh
./scripts/build-ios.sh
```
