# Memory Leak Fixes - Viro React

Fixed memory leaks related to resource management on unmount for both iOS and Android.

## Summary

The main issue was that `VRTARSceneNavigator` was not being properly deallocated when React components unmounted. The native ARSession and GL resources were not released, causing memory to accumulate over time.

### Root causes fixed:
- React component had no `componentWillUnmount` to trigger native cleanup
- iOS relied on `willMoveToSuperview:nil` which isn't called reliably in Fabric
- Material change listeners were added but never removed
- Video textures were not paused/released on dealloc
- Animation components had empty `dealloc` methods causing retain cycles

---

## iOS Changes (8 files)

| File | Change |
|------|--------|
| `VRTARSceneNavigator.mm` | Added `prepareForRecycle` for Fabric architecture support |
| `VRTARSceneNavigatorModule.mm` | Added `cleanup:` method to release AR session and GL resources |
| `VRTMaterialVideo.mm` | Added `dealloc` to pause video, clear delegate, and remove material listener |
| `VRTMaterialManager.mm` | Added `removeMaterialChangedListener:listener:` method |
| `VRTMaterialManager.h` | Added method declaration for `removeMaterialChangedListener` |
| `VRTMaterialVideoManager.mm` | Added `pause:` method callable from React |
| `VRTVideoSurface.mm` | Added `dealloc` to pause video and clear surface/delegate references |
| `VRTAnimatedComponent.mm` | Fixed empty `dealloc` to clear `managedAnimation` and break retain cycles |

## Android Changes (2 files)

| File | Change |
|------|--------|
| `VRTARSceneNavigator.java` | Added `dispose()` method to disable rotation listener and pause AR view |
| `ARSceneNavigatorModule.java` | Added `cleanup()` method callable from React to trigger disposal |

## React Native Changes (2 files)

| File | Change |
|------|--------|
| `ViroARSceneNavigator.tsx` | Added `componentWillUnmount()` to call native `cleanup()` on both platforms |
| `ViroMaterialVideo.tsx` | Updated `componentWillUnmount()` to pause video on iOS (was Android-only) |

---

## Testing Recommendations

Rebuild both platforms and monitor memory during:
1. Rapid AR scene navigation (push/pop scenes quickly)
2. Video playback start/stop cycles
3. Long-running AR sessions
4. Mounting/unmounting AR components repeatedly

## Tools for Verification

**iOS:**
- Xcode Instruments > Leaks
- Xcode Instruments > Allocations (track `VROViewAR`, `VROARSession`, `EAGLContext`)

**Android:**
- Android Studio Profiler > Memory
- Monitor `ViroViewARCore` instances after navigation
