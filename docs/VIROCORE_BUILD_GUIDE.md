# ViroCore iOS Build Guide

This document describes how to build the ViroCore rendering engine (`ViroKit.framework`) for iOS and copy it to the ViroReact project for use.

## Overview

**ViroCore** is the underlying C++/Objective-C rendering engine that powers ViroReact. It produces:
- `ViroKit.framework` - The main rendering framework
- Headers and resources for AR/VR functionality

The built framework is then copied to `viro/ios/dist/ViroRenderer/` for use by ViroReact.

## Prerequisites

- **Xcode 15+** with iOS SDK 18.x
- **iOS 18.0+ minimum deployment target** (required for ARKit camera zoom APIs)
- **CocoaPods** installed (`gem install cocoapods`)
- **Fastlane** (optional, for automated builds): `gem install fastlane`
- Both repositories cloned in the same parent directory:
  ```
  workspace/
  ├── virocore/     # ViroCore renderer
  └── viro/         # ViroReact bridge
  ```

## Directory Structure

```
virocore/
├── ViroRenderer/           # Core C++ rendering engine source
│   ├── VRO*.h/cpp         # Renderer classes
│   ├── Shaders.metal      # Metal shaders
│   └── *.glsl             # OpenGL shaders
├── ios/
│   ├── ViroKit/           # iOS-specific ViroKit implementation
│   ├── ViroRenderer.xcworkspace
│   ├── ViroRenderer.xcodeproj
│   ├── Podfile
│   ├── ViroKit.podspec
│   └── fastlane/          # Fastlane automation scripts
├── android/               # Android implementation
└── README.md
```

## Step 1: Clone Repositories

Ensure both repositories are in the same parent directory:

```bash
cd ~/workspace
git clone https://github.com/ReactVision/virocore.git
git clone https://github.com/ReactVision/viro.git
```

## Step 2: Install CocoaPods Dependencies

```bash
cd virocore/ios
pod install
```

This installs:
- **GVRAudioSDK** - Google VR Audio for spatial audio
- **ARCore** pods (optional) - Cloud Anchors, Geospatial, Semantics

### ARCore Weak Linking

The Podfile includes a `post_install` hook that converts ARCore framework links to weak links. This allows ViroKit to be used in apps that don't include ARCore.

## Step 3: Build ViroKit Framework

### Option A: Using Xcode (Manual)

1. Open `virocore/ios/ViroRenderer.xcworkspace` in Xcode
2. Select the **ViroKit** scheme
3. Set Build Configuration to **Release**
4. Set destination to **Generic iOS Device** (for device) or **Any iOS Simulator** (for simulator)
5. Build (⌘+B)

```bash
# Device build
xcodebuild \
  -workspace ViroRenderer.xcworkspace \
  -scheme ViroKit \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  build

# Simulator build
xcodebuild \
  -workspace ViroRenderer.xcworkspace \
  -scheme ViroKit \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

### Option B: Using Fastlane (Automated)

Fastlane provides automated build lanes:

```bash
cd virocore/ios

# Build both framework and static lib for device + simulator
fastlane virorender_viroreact_virokit

# Or build just the framework
fastlane virorender_viroreact_virokit_framework

# Or build just the static library variant
fastlane virorender_viroreact_virokit_static_lib
```

### Static Library Variant

If your app doesn't use `use_frameworks!` in its Podfile, build the static library variant:

```bash
xcodebuild \
  -workspace ViroRenderer.xcworkspace \
  -scheme ViroKit_static_lib \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  build
```

## Step 4: Locate Build Output

After a successful build, the framework is in Xcode's DerivedData:

```bash
# Find the built framework
find ~/Library/Developer/Xcode/DerivedData \
  -name "ViroKit.framework" \
  -path "*Release-iphoneos*" \
  -type d

# Typical path:
# ~/Library/Developer/Xcode/DerivedData/ViroRenderer-xxx/Build/Products/Release-iphoneos/ViroKit/ViroKit.framework
```

## Step 5: Copy to ViroReact

The build process should automatically copy files to `viro/ios/dist/`. If not, manually copy:

```bash
# Define paths
DERIVED_DATA=~/Library/Developer/Xcode/DerivedData
VIROCORE_BUILD=$(find $DERIVED_DATA -name "ViroKit.framework" -path "*ViroRenderer*Release-iphoneos*" -type d | head -1)
VIRO_DIST=~/workspace/viro/ios/dist/ViroRenderer

# Create directory structure
mkdir -p $VIRO_DIST/armv7_arm64

# Copy framework
cp -R $VIROCORE_BUILD $VIRO_DIST/
cp -R $VIROCORE_BUILD $VIRO_DIST/armv7_arm64/

# Copy podspec
cp ~/workspace/virocore/ios/ViroKit.podspec $VIRO_DIST/
```

## Build Schemes Explained

| Scheme | Output | Use Case |
|--------|--------|----------|
| `ViroKit` | Dynamic framework | Apps using `use_frameworks!` |
| `ViroKit_static_lib` | Static library | Apps without `use_frameworks!` |

## Key Files in ViroCore

### ViroRenderer/ (Core Engine)

| File Pattern | Description |
|--------------|-------------|
| `VROARSession*.h/cpp` | ARKit session management |
| `VROScene*.h/cpp` | Scene graph implementation |
| `VRONode*.h/cpp` | Node hierarchy |
| `VROMaterial*.h/cpp` | Material/shader system |
| `VRORenderer*.h/cpp` | Main rendering pipeline |
| `VROPhysics*.h/cpp` | Physics engine integration |
| `Shaders.metal` | Metal shader programs |
| `*.glsl` | OpenGL shader programs |

### ios/ViroKit/ (iOS Platform Layer)

| File | Description |
|------|-------------|
| `VROViewAR.h/mm` | AR view implementation |
| `VROARSessioniOS.h/mm` | ARKit session wrapper |
| `VRODriverOpenGLiOS.h/mm` | OpenGL ES driver |
| `VROVideoTextureiOS.h/mm` | Video texture handling |

## Modifying ViroCore

### Adding a New Method to VROViewAR

1. **Declare in header** (`virocore/ios/ViroKit/VROViewAR.h`):
   ```objective-c
   - (ARSession *)getARSession;
   ```

2. **Implement** (`virocore/ios/ViroKit/VROViewAR.mm`):
   ```objective-c
   - (ARSession *)getARSession {
       return _session;
   }
   ```

3. **Rebuild ViroKit** and copy to viro

4. **Update ViroReact bridge** to call the new method

### Example: Exposing ARSession

We added the ability to access the native ARSession:

```objective-c
// In VROViewAR.h
- (ARSession *)getARSession;

// In VROViewAR.mm
- (ARSession *)getARSession {
    return _session;
}
```

Then in ViroReact (`VRTARSceneNavigator.mm`):
```objective-c
- (ARSession *)getNativeARSession {
    VROViewAR *arView = (VROViewAR *)self.vroView;
    return [arView getARSession];
}
```

## Troubleshooting

### Pod Install Fails

**Error:** `Unable to find a specification for 'ARCore/CloudAnchors'`

**Solution:** Update CocoaPods repo:
```bash
pod repo update
pod install
```

### Framework Not Found

**Error:** `framework not found ViroKit`

**Solution:** Ensure the framework is in the correct architecture folder:
```bash
# Check architecture of built framework
lipo -info ViroKit.framework/ViroKit

# Should show: arm64 (for device) or x86_64 (for simulator)
```

### Weak Linking Issues

**Error:** ARCore symbols not found at runtime

**Solution:** The Podfile's `post_install` hook should convert `-framework ARCore*` to `-weak_framework ARCore*`. Verify the xcconfig files have been updated:
```bash
grep -r "weak_framework" ios/Pods/Target\ Support\ Files/
```

### GLKit Deprecation Warnings

GLKit is deprecated but still required by ViroCore. These warnings can be ignored:
```
'GLKView' is deprecated: first deprecated in iOS 12.0
```

## Complete Build Script

Save as `scripts/build-virokit.sh`:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VIROCORE_DIR="$(dirname "$SCRIPT_DIR")"
VIRO_DIR="$(dirname "$VIROCORE_DIR")/viro"

echo "=== Installing Pods ==="
cd "$VIROCORE_DIR/ios"
pod install

echo "=== Building ViroKit (Device) ==="
xcodebuild \
  -workspace ViroRenderer.xcworkspace \
  -scheme ViroKit \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  clean build

echo "=== Locating Build Output ==="
DERIVED_DATA=~/Library/Developer/Xcode/DerivedData
FRAMEWORK_PATH=$(find $DERIVED_DATA -name "ViroKit.framework" \
  -path "*ViroRenderer*Release-iphoneos*" -type d | head -1)

if [ -z "$FRAMEWORK_PATH" ]; then
    echo "ERROR: ViroKit.framework not found!"
    exit 1
fi

echo "Found: $FRAMEWORK_PATH"

echo "=== Copying to ViroReact ==="
DEST_DIR="$VIRO_DIR/ios/dist/ViroRenderer"
mkdir -p "$DEST_DIR/armv7_arm64"

cp -R "$FRAMEWORK_PATH" "$DEST_DIR/"
cp -R "$FRAMEWORK_PATH" "$DEST_DIR/armv7_arm64/"
cp "$VIROCORE_DIR/ios/ViroKit.podspec" "$DEST_DIR/"

echo "=== Done ==="
echo "ViroKit.framework copied to: $DEST_DIR"
ls -la "$DEST_DIR"
```

Make it executable:
```bash
chmod +x virocore/scripts/build-virokit.sh
```

## CI/CD Integration

ViroCore uses GitHub Actions for CI. See `.github/workflows/` for:
- Automated builds on push
- Artifact uploads (ios_dist.tgz, viroreact.aar, virocore.aar)

To download prebuilt artifacts:
1. Go to [ViroCore Actions](https://github.com/viromedia/virocore/actions)
2. Find a successful build
3. Download `ios_dist.tgz`
4. Extract to `viro/ios/dist/ViroRenderer/`

## Related Documentation

- [ViroReact Prebuild Guide](./PREBUILD_GUIDE.md) - Building libViroReact.a
- [ViroCore README](https://github.com/ReactVision/virocore/blob/master/README.md) - Official documentation
- [ViroCore API Reference](https://developer.viromedia.com/) - Java/Kotlin API docs
