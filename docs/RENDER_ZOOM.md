# Render Zoom (Projection-Based Camera Zoom)

This document describes ViroReact's projection-based render zoom feature for iOS, which provides a real zoom effect that is captured in screenshots, video recordings, and high-resolution photos.

## Overview

ViroReact provides two zoom mechanisms:

| Method | How It Works | Captured in Media? | Use Case |
|--------|--------------|-------------------|----------|
| `setViewZoom` | UI-level `CGAffineTransform` scaling | No | Quick preview zoom |
| `setRenderZoom` | Projection matrix + texture cropping | **Yes** | Production zoom with capture |

**Render zoom** modifies the actual rendering pipeline, making the zoom effect visible in all output including screenshots, video recordings, and high-resolution photos.

## How It Works

### 1. Projection Matrix Scaling

The projection matrix defines how 3D coordinates are mapped to 2D screen coordinates. By scaling the focal length elements, we narrow the field of view (FOV), creating a zoom effect.

```
Before zoom (identity-like projection):
┌─────────────────────────────────────┐
│  fx   0    cx   0  │   fx = focal length X
│  0    fy   cy   0  │   fy = focal length Y
│  0    0    ...     │   cx, cy = principal point
│  0    0    ...     │
└─────────────────────────────────────┘

After 2x zoom:
┌─────────────────────────────────────┐
│  fx*2  0    cx   0  │   FOV narrowed by 2x
│  0    fy*2  cy   0  │   Objects appear 2x larger
│  0    0    ...      │
│  0    0    ...      │
└─────────────────────────────────────┘
```

This is applied in `VROViewAR.mm`:
```cpp
float renderZoom = arSession->getRenderZoom();
if (renderZoom > 1.0f) {
    projection[0] *= renderZoom;  // Scale fx
    projection[5] *= renderZoom;  // Scale fy
}
```

### 2. Camera Background Texture Cropping

When the projection matrix is zoomed, the camera background must be cropped to match. Otherwise, the 3D content would appear zoomed while the camera background stays at 1x.

The texture coordinate transform crops the center portion of the camera feed:

```
1x zoom (full frame):          2x zoom (center 50%):
┌─────────────────────┐        ┌─────────────────────┐
│                     │        │   ┌───────────┐     │
│                     │        │   │  Visible  │     │
│     Full Camera     │   →    │   │   Area    │     │
│       Feed          │        │   │  (50%)    │     │
│                     │        │   └───────────┘     │
└─────────────────────┘        └─────────────────────┘
```

The transform matrix calculation:
```cpp
float scale = 1.0f / renderZoom;      // 2x zoom → 0.5 scale
float offset = (1.0f - scale) / 2.0f; // Center the crop

// Transform: new_uv = offset + old_uv * scale
```

### 3. Hit Testing Adjustment

Touch coordinates must be transformed to account for the zoomed viewport. When the user taps a point on screen, the hit test needs to map that to the correct location in the unzoomed coordinate space.

```cpp
// In VROARFrameiOS.cpp
float renderZoom = session->getRenderZoom();
if (renderZoom > 1.0f) {
    float scale = 1.0f / renderZoom;
    float offset = (1.0f - scale) / 2.0f;

    // Transform touch point to unzoomed space
    pointViewport.x = offset + pointViewport.x * scale;
    pointViewport.y = offset + pointViewport.y * scale;
}
```

## API Reference

### TypeScript API

All methods are available via `arSceneNavigator` or `sceneNavigator` props passed to your AR scene.

#### `setRenderZoom(zoomFactor: number): void`

Set the render zoom factor. The zoom is applied immediately and affects both the live preview and any captured media.

```typescript
// In your AR scene component
const MyARScene = (props) => {
  const handleZoomIn = () => {
    props.arSceneNavigator.setRenderZoom(2.0); // 2x zoom
  };

  const handleZoomOut = () => {
    props.arSceneNavigator.setRenderZoom(1.0); // Reset to normal
  };

  // ...
};
```

**Parameters:**
- `zoomFactor` - The zoom level (1.0 = no zoom, 2.0 = 2x zoom, etc.)
- Automatically clamped to range `[1.0, maxRenderZoom]`

#### `getRenderZoom(): Promise<ViroRenderZoomResult>`

Get the current render zoom factor.

```typescript
const checkZoom = async () => {
  const result = await props.arSceneNavigator.getRenderZoom();
  console.log('Current zoom:', result.zoomFactor);
};
```

**Returns:** `{ zoomFactor: number }`

#### `getMaxRenderZoom(): Promise<ViroMaxRenderZoomResult>`

Get the maximum allowed render zoom factor.

```typescript
const checkMaxZoom = async () => {
  const result = await props.arSceneNavigator.getMaxRenderZoom();
  console.log('Max zoom:', result.maxZoomFactor);
};
```

**Returns:** `{ maxZoomFactor: number }` (default: 5.0)

#### `setMaxRenderZoom(maxZoom: number): void`

Set the maximum allowed render zoom factor.

```typescript
// Allow up to 10x zoom
props.arSceneNavigator.setMaxRenderZoom(10.0);
```

**Parameters:**
- `maxZoom` - The maximum zoom level (must be >= 1.0)

### Types

```typescript
interface ViroRenderZoomResult {
  zoomFactor: number;
  error?: string;
}

interface ViroMaxRenderZoomResult {
  maxZoomFactor: number;
  error?: string;
}
```

## Usage Examples

### Basic Zoom Control

```typescript
import { ViroARSceneNavigator } from '@reactvision/react-viro';

const App = () => {
  return (
    <ViroARSceneNavigator
      initialScene={{ scene: MyARScene }}
    />
  );
};

const MyARScene = (props) => {
  const [zoom, setZoom] = useState(1.0);

  const handlePinch = (pinchState, scaleFactor) => {
    if (pinchState === 3) { // Pinch end
      const newZoom = Math.max(1.0, Math.min(zoom * scaleFactor, 5.0));
      setZoom(newZoom);
      props.arSceneNavigator.setRenderZoom(newZoom);
    }
  };

  return (
    <ViroARScene onPinch={handlePinch}>
      {/* Your AR content */}
    </ViroARScene>
  );
};
```

### Zoom with Screenshot

```typescript
const captureZoomedPhoto = async () => {
  // Set zoom first
  props.arSceneNavigator.setRenderZoom(2.0);

  // Wait a frame for zoom to apply
  await new Promise(resolve => setTimeout(resolve, 100));

  // Take screenshot - it will include the zoom
  const result = await props.arSceneNavigator.takeScreenshot(
    'zoomed_photo',
    true // save to camera roll
  );

  console.log('Saved zoomed photo:', result.url);
};
```

### Smooth Animated Zoom

```typescript
const animateZoom = (targetZoom: number, duration: number = 300) => {
  const startZoom = currentZoom;
  const startTime = Date.now();

  const animate = () => {
    const elapsed = Date.now() - startTime;
    const progress = Math.min(elapsed / duration, 1.0);

    // Ease-out curve
    const eased = 1 - Math.pow(1 - progress, 3);
    const newZoom = startZoom + (targetZoom - startZoom) * eased;

    props.arSceneNavigator.setRenderZoom(newZoom);

    if (progress < 1.0) {
      requestAnimationFrame(animate);
    }
  };

  animate();
};
```

## Technical Architecture

### Code Flow

```
TypeScript                    React Native Bridge              Native (iOS)
─────────────────────────────────────────────────────────────────────────────
setRenderZoom(2.0)
       │
       ▼
ViroARSceneNavigator.tsx
       │
       ▼
VRTARSceneNavigatorModule.mm ──► RCT_EXPORT_METHOD
       │
       ▼
VRTARSceneNavigator.mm
       │
       ▼
VROARSession.h ──► setRenderZoom() stores _renderZoomFactor
       │
       ▼
VROViewAR.mm ──► Render loop reads zoom, applies to:
       │         • Projection matrix
       │         • Camera texture transform
       │
       ▼
VROARFrameiOS.cpp ──► Hit testing reads zoom for coordinate transform
```

### Files Modified

| Layer | File | Purpose |
|-------|------|---------|
| TypeScript | `components/AR/ViroARSceneNavigator.tsx` | Public API methods |
| TypeScript | `components/Types/ViroEvents.ts` | Result types |
| Bridge | `ios/ViroReact/AR/Modules/VRTARSceneNavigatorModule.mm` | RCT_EXPORT_METHODs |
| Bridge | `ios/ViroReact/AR/Views/VRTARSceneNavigator.mm` | Native view methods |
| Bridge | `ios/ViroReact/AR/Views/VRTARSceneNavigator.h` | Method declarations |
| Core | `VROARSession.h` | Zoom state storage |
| Core | `VROViewAR.mm` | Projection & texture application |
| Core | `VROARFrameiOS.cpp` | Hit testing adjustment |

## Platform Support

| Platform | Support |
|----------|---------|
| iOS | Full support |
| Android | Not yet implemented |

## Limitations

1. **Digital zoom only** - This is a crop/scale zoom, not optical zoom. At high zoom levels (>3x), image quality degrades.

2. **No depth adjustment** - The zoom doesn't affect depth perception or occlusion calculations.

3. **ARKit restrictions** - Hardware camera zoom via `videoZoomFactor` is restricted by ARKit to 1.0x. This projection-based approach is a workaround.

4. **Performance** - Very high zoom levels may impact performance on older devices due to larger effective render area calculations.

## Troubleshooting

### Zoom not applying
- Ensure the AR session is initialized before calling `setRenderZoom`
- Check console for `[ViroZoom]` log messages

### Hit testing misaligned at zoom
- Verify `VROARFrameiOS.cpp` has the coordinate transform code
- The transform must match the texture cropping formula

### Zoom not captured in screenshots
- Confirm you're using `setRenderZoom`, not `setViewZoom`
- `setViewZoom` uses UI transforms that aren't captured

## Related Documentation

- [ViroARSceneNavigator API](https://docs.viromedia.com/docs/viroarscenenavigator)
- [Screenshots & Recording](https://docs.viromedia.com/docs/screenshots-and-recording)
- [High-Resolution Photo Feature](./HIGH_RES_PHOTO.md) (if implemented)
