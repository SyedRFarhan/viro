# Frame Streaming Quick Test

A minimal test to verify AR frames are being streamed to JavaScript.

## What This Feature Does

The Frame Streaming API captures AR camera frames and sends them to JavaScript for external processing (e.g., Google Gemini Vision AI). Key capabilities:

| Feature | Description |
|---------|-------------|
| **JPEG Encoding** | Frames are JPEG-compressed with configurable quality (0.0-1.0) |
| **Exact Dimensions** | Output is scaled+cropped to exact target size (e.g., 640x480) |
| **Rate Limiting** | Configurable 1-5 FPS, drops frames if processing is slow |
| **Non-blocking** | Capture runs on background thread, doesn't block rendering |
| **Pose Storage** | Each frame's camera pose is stored for later 2D→3D mapping |

### Frame Event Data

Each `onFrameUpdate` callback receives:

```typescript
{
  frameId: string;        // Unique ID (e.g., "42_1705234567.123")
  timestamp: number;      // ARFrame timestamp
  sessionId: number;      // Increments on AR session reset

  imageData: string;      // Base64 JPEG
  width: number;          // Exact output width
  height: number;         // Exact output height

  intrinsics: {           // Camera intrinsics (crop-adjusted)
    fx, fy, cx, cy
  };

  cameraToWorld: number[];      // 4x4 pose matrix (16 floats)
  jpegToARTransform: number[];  // 3x3 UV transform matrix
  trackingState: string;        // "normal" | "limited" | "notAvailable"
}
```

### Platform Support

| Platform | Status |
|----------|--------|
| iOS | ✅ Supported (iOS 14.0+) |
| Android | ❌ Not yet implemented |

## Test Component

```tsx
import React, { useRef, useState } from "react";
import { View, Text, TouchableOpacity, StyleSheet } from "react-native";
import {
  ViroARSceneNavigator,
  ViroARScene,
} from "@reactvision/react-viro";

function BasicARScene() {
  return <ViroARScene />;
}

export default function FrameStreamTest() {
  const navRef = useRef<any>(null);
  const [streaming, setStreaming] = useState(false);
  const [count, setCount] = useState(0);
  const [lastFrame, setLastFrame] = useState<{
    id: string;
    size: string;
    tracking: string;
  } | null>(null);

  const toggleStream = () => {
    if (!navRef.current) return;

    if (streaming) {
      navRef.current._stopFrameStream();
      setStreaming(false);
    } else {
      navRef.current._startFrameStream({
        enabled: true,
        width: 320,
        height: 240,
        fps: 1,        // 1 FPS for easy verification
        quality: 0.5,
      });
      setStreaming(true);
      setCount(0);
    }
  };

  return (
    <View style={styles.container}>
      <ViroARSceneNavigator
        ref={navRef}
        initialScene={{ scene: BasicARScene }}
        onFrameUpdate={(e) => {
          setCount((c) => c + 1);
          setLastFrame({
            id: e.frameId,
            size: `${e.width}x${e.height}`,
            tracking: e.trackingState,
          });
        }}
        style={styles.ar}
      />

      <View style={styles.panel}>
        <Text style={styles.title}>Frame Stream Test</Text>
        <Text style={styles.info}>
          Status: {streaming ? "STREAMING" : "STOPPED"}
        </Text>
        <Text style={styles.info}>Frames: {count}</Text>
        {lastFrame && (
          <>
            <Text style={styles.info}>Size: {lastFrame.size}</Text>
            <Text style={styles.info}>Tracking: {lastFrame.tracking}</Text>
            <Text style={styles.info} numberOfLines={1}>
              ID: {lastFrame.id}
            </Text>
          </>
        )}

        <TouchableOpacity style={styles.btn} onPress={toggleStream}>
          <Text style={styles.btnText}>
            {streaming ? "Stop" : "Start"}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  ar: { flex: 1 },
  panel: {
    position: "absolute",
    bottom: 40,
    left: 20,
    right: 20,
    backgroundColor: "rgba(0,0,0,0.8)",
    padding: 16,
    borderRadius: 12,
  },
  title: {
    color: "#fff",
    fontSize: 18,
    fontWeight: "bold",
    marginBottom: 8,
  },
  info: {
    color: "#ccc",
    fontSize: 14,
    marginVertical: 2,
  },
  btn: {
    backgroundColor: "#007AFF",
    padding: 12,
    borderRadius: 8,
    marginTop: 12,
    alignItems: "center",
  },
  btnText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "600",
  },
});
```

## Expected Behavior

1. Tap **Start** - frame count should increment once per second (1 FPS)
2. Each frame shows:
   - Size: `320x240`
   - Tracking: `normal` (when device is stable)
   - ID: increments like `0_1234567.890`, `1_1234568.890`
3. Tap **Stop** - count freezes

## Troubleshooting

| Symptom | Check |
|---------|-------|
| No frames | Is `tracking` showing `notAvailable`? Point camera at textured surface |
| Count not incrementing | Check Xcode console for `[ViroFrameStream]` logs |
| App crashes | Ensure iOS 14.0+ and New Architecture enabled |

## Console Logs

When streaming starts, you should see in Xcode:
```
[ViroFrameStream] Starting frame stream with config: {enabled = 1; fps = 1; ...}
[ViroFrameStream] Frame stream started: 320x240 @ 1.0 FPS, quality: 0.50
```

## Configuration Options

```typescript
startFrameStream({
  enabled: boolean,  // Enable/disable streaming
  width: number,     // Target width (e.g., 320, 640, 1280)
  height: number,    // Target height (e.g., 240, 480, 720)
  fps: number,       // 1-5 frames per second
  quality: number,   // JPEG quality 0.0-1.0
});
```

### Recommended Settings

| Use Case | Width | Height | FPS | Quality | JPEG Size |
|----------|-------|--------|-----|---------|-----------|
| Testing | 320 | 240 | 1 | 0.5 | ~10-20 KB |
| Gemini Live | 640 | 480 | 5 | 0.7 | ~30-50 KB |
| High Quality | 1280 | 720 | 3 | 0.8 | ~80-120 KB |

## How It Works (Architecture)

```
┌─────────────────────────────────────────────────────────┐
│  AR Render Loop (60 FPS)                                │
│    │                                                    │
│    ▼                                                    │
│  VROFrameCaptureService                                 │
│    ├─ Rate limit check (skip if < 1/fps elapsed)       │
│    ├─ Busy check (skip if still encoding previous)     │
│    │                                                    │
│    ▼                                                    │
│  Background Queue (QOS_CLASS_USER_INITIATED)           │
│    ├─ Scale image (MAX scale for cover)                │
│    ├─ Center crop to exact dimensions                  │
│    ├─ JPEG encode                                      │
│    ├─ Store in ring buffer (30 frames)                 │
│    │                                                    │
│    ▼                                                    │
│  Main Thread → onFrameUpdate callback                  │
└─────────────────────────────────────────────────────────┘
```

### Ring Buffer

- Stores last **30 frames** with their capture-time data
- Each entry contains: pose matrix, intrinsics, depth buffer (LiDAR), feature points
- Enables `resolveDetections(frameId, points)` to map 2D→3D even after camera moves
- Older frames are evicted when buffer is full

## Next Steps

Once frames are streaming correctly, see [FRAME_STREAMING_GUIDE.md](./FRAME_STREAMING_GUIDE.md) for:
- Integrating with Gemini Vision AI
- Using `resolveDetections()` for 2D→3D mapping
- Complete example with WebSocket streaming
