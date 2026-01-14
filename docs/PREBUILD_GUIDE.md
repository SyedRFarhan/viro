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

## Step 1: Install Dependencies

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

## Step 3: Build the Static Library

Run the following command from the `viro/ios` directory:

```bash
cd viro/ios

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

### Build Command Breakdown

| Parameter | Purpose |
|-----------|---------|
| `RCT_NEW_ARCH_ENABLED=1` | Enables React Native New Architecture (Fabric) |
| `REACT_NATIVE_PATH=...` | Points to React Native for Hermes scripts |
| `-configuration Release` | Builds optimized release version |
| `-sdk iphoneos` | Builds for physical iOS devices |
| `-destination 'generic/platform=iOS'` | Generic iOS destination |

## Step 4: Copy Built Library to dist

After a successful build, copy the library to the distribution folder:

```bash
# Find and copy the built library
find ~/Library/Developer/Xcode/DerivedData \
  -name "libViroReact.a" \
  -path "*Release-iphoneos*" \
  -exec cp {} dist/lib/ \;
```

Alternatively, locate it manually:
```bash
ls ~/Library/Developer/Xcode/DerivedData/ViroReact-*/Build/Products/Release-iphoneos/libViroReact.a
```

## Step 5: Verify the Library

Check that the library contains the expected symbols:

```bash
nm -g dist/lib/libViroReact.a | grep "ARSceneNavigator"
```

Expected output should include symbols like:
```
-[VRTARSceneNavigator getNativeARSession]
-[VRTARSceneNavigatorModule isNativeARSessionAvailable:resolve:reject:]
```

## Step 6: Build TypeScript

Compile the TypeScript components:

```bash
cd viro
npm run build
```

This generates the `dist/` folder with compiled JavaScript and type definitions.

## Step 7: Package for Local Use

Create a tarball for local installation:

```bash
cd viro
npm pack
```

This creates `reactvision-react-viro-X.X.X.tgz`.

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

### Hermes Script Failure

**Error:** `[Hermes] Replace Hermes for the right configuration, if needed` fails

**Solution:** Ensure `REACT_NATIVE_PATH` is set when running xcodebuild:
```bash
REACT_NATIVE_PATH=$(pwd)/../node_modules/react-native xcodebuild ...
```

### Node Binary Not Found

**Error:** Build fails with "node: command not found"

**Solution:** Update `ios/.xcode.env.local` with the correct path:
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
