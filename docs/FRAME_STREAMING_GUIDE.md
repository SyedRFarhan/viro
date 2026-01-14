# AR Frame Streaming for Vision AI Integration

This guide explains how to stream AR camera frames from ViroReact to external vision AI services like Google Gemini Live.

## Overview

The Frame Streaming API captures AR camera frames at a configurable rate, JPEG-encodes them to exact target dimensions, and delivers them via a callback. Each frame includes metadata needed for accurate 2D→3D coordinate mapping, even when the AI service responds after the camera has moved.

### Key Features

- **Configurable capture**: 1-5 FPS, resolution up to 720p, JPEG quality 0.0-1.0
- **Non-blocking**: Frame capture doesn't block the render pipeline
- **Capture-time pose storage**: Ring buffer stores camera pose/intrinsics for each frame
- **Deferred 2D→3D mapping**: `resolveDetections()` uses stored capture-time data
- **Multiple resolution methods**: LiDAR → raycast → point cloud fallback ladder

## Platform Support

| Platform | Status |
|----------|--------|
| iOS | ✅ Supported |
| Android | ❌ Not yet implemented |

## Quick Start

### 1. Basic Setup

```tsx
import { ViroARSceneNavigator } from "@reactvision/react-viro";

function ARApp() {
  const navigatorRef = useRef<any>(null);

  const handleFrameUpdate = (event: ViroFrameEvent) => {
    console.log(`Frame ${event.frameId}: ${event.width}x${event.height}`);
    // Send event.imageData to your vision AI service
  };

  return (
    <ViroARSceneNavigator
      ref={navigatorRef}
      initialScene={{ scene: MyARScene }}
      onFrameUpdate={handleFrameUpdate}
    />
  );
}
```

### 2. Start Streaming

```tsx
// Inside your AR scene component
const startStreaming = () => {
  props.arSceneNavigator.startFrameStream({
    enabled: true,
    width: 640,      // Target width in pixels
    height: 480,     // Target height in pixels
    fps: 5,          // Frames per second (1-5)
    quality: 0.7,    // JPEG quality (0.0-1.0)
  });
};

const stopStreaming = () => {
  props.arSceneNavigator.stopFrameStream();
};
```

### 3. Handle Frame Events

```tsx
interface ViroFrameEvent {
  frameId: string;           // Unique ID for this capture
  timestamp: number;         // ARFrame timestamp
  sessionId: number;         // Increments on AR session reset

  imageData: string;         // Base64 JPEG
  width: number;             // Exact output width
  height: number;            // Exact output height

  intrinsics: {
    fx: number;              // Focal length X (JPEG pixels)
    fy: number;              // Focal length Y (JPEG pixels)
    cx: number;              // Principal point X (crop-adjusted)
    cy: number;              // Principal point Y (crop-adjusted)
  };

  cameraToWorld: number[];   // 4x4 matrix (16 elements, column-major)
  jpegToARTransform: number[]; // 3x3 affine matrix for UV mapping
  trackingState: "normal" | "limited" | "notAvailable";
}
```

### 4. Resolve Detections to 3D

When your vision AI returns detection results (e.g., bounding boxes), resolve them to 3D world coordinates:

```tsx
const handleAIResponse = async (response: AIResponse) => {
  const { frameId, detections } = response;

  // Convert bbox centers to normalized UV coordinates (0-1)
  const points = detections.map(d => ({
    x: d.bbox.centerX,  // Already normalized 0-1
    y: d.bbox.centerY,
  }));

  // Resolve to 3D using capture-time camera pose
  const result = await props.arSceneNavigator.resolveDetections(frameId, points);

  for (let i = 0; i < result.results.length; i++) {
    const r = result.results[i];
    if (r.ok && r.worldPos) {
      console.log(`${detections[i].label} at [${r.worldPos.join(", ")}]`);
      console.log(`  Method: ${r.method}, Confidence: ${r.confidence}`);
      // Place a 3D marker at r.worldPos
    }
  }
};
```

## Resolution Methods

When resolving 2D points to 3D, the system uses a fallback ladder:

| Method | Confidence | Description |
|--------|------------|-------------|
| `lidar` | 0.95 | LiDAR depth sampling (Pro devices only) |
| `raycast_geometry` | 0.95 | Raycast hits actual plane mesh |
| `raycast_infinite` | 0.85 | Raycast hits infinite plane extension |
| `raycast_estimated` | 0.6 | Raycast hits estimated plane (can shift) |
| `pointcloud` | 0.3-0.6 | Nearest feature point to ray |

## Complete Example: Gemini Live Integration

```tsx
import React, { useRef, useState, useCallback } from "react";
import {
  ViroARSceneNavigator,
  ViroARScene,
  ViroText,
  ViroNode,
} from "@reactvision/react-viro";
import type {
  ViroFrameEvent,
  ViroFrameStreamConfig,
  ViroDetectionResolutionResult,
} from "@reactvision/react-viro";

// Frame cache for correlating AI responses with capture data
const frameCache = new Map<string, ViroFrameEvent>();
const MAX_CACHE_SIZE = 30;

function GeminiARScene(props: any) {
  const [markers, setMarkers] = useState<Array<{
    label: string;
    position: [number, number, number];
  }>>([]);

  // Start streaming when scene loads
  React.useEffect(() => {
    props.arSceneNavigator.startFrameStream({
      enabled: true,
      width: 640,
      height: 480,
      fps: 5,
      quality: 0.7,
    });

    return () => {
      props.arSceneNavigator.stopFrameStream();
    };
  }, []);

  return (
    <ViroARScene>
      {markers.map((marker, i) => (
        <ViroNode key={i} position={marker.position}>
          <ViroText
            text={marker.label}
            scale={[0.3, 0.3, 0.3]}
            style={{ fontSize: 20, color: "#ffffff" }}
          />
        </ViroNode>
      ))}
    </ViroARScene>
  );
}

export default function GeminiARApp() {
  const navigatorRef = useRef<any>(null);
  const websocketRef = useRef<WebSocket | null>(null);

  const handleFrameUpdate = useCallback((event: ViroFrameEvent) => {
    // Cache the frame for later resolution
    frameCache.set(event.frameId, event);
    if (frameCache.size > MAX_CACHE_SIZE) {
      const oldest = frameCache.keys().next().value;
      frameCache.delete(oldest);
    }

    // Send to Gemini
    if (websocketRef.current?.readyState === WebSocket.OPEN) {
      websocketRef.current.send(JSON.stringify({
        realtime_input: {
          media_chunks: [{
            mime_type: "image/jpeg",
            data: event.imageData,
          }],
        },
        metadata: { frameId: event.frameId },
      }));
    }
  }, []);

  const handleGeminiResponse = useCallback(async (data: any) => {
    const { frameId, detections } = data;

    if (!navigatorRef.current || !detections?.length) return;

    // Get the arSceneNavigator from the ref
    const arNav = navigatorRef.current;

    const points = detections.map((d: any) => ({
      x: (d.bbox.x + d.bbox.w / 2),
      y: (d.bbox.y + d.bbox.h / 2),
    }));

    try {
      const result = await arNav.resolveDetections(frameId, points);

      const newMarkers = result.results
        .filter((r: any) => r.ok && r.worldPos)
        .map((r: any, i: number) => ({
          label: detections[i].label,
          position: r.worldPos as [number, number, number],
        }));

      // Update markers in scene (you'd use state management here)
      console.log("Resolved markers:", newMarkers);
    } catch (error) {
      console.error("Failed to resolve detections:", error);
    }
  }, []);

  return (
    <ViroARSceneNavigator
      ref={navigatorRef}
      initialScene={{ scene: GeminiARScene }}
      onFrameUpdate={handleFrameUpdate}
    />
  );
}
```

## Testing Your Integration

### Simple Test Setup

Create a test component that verifies frame streaming is working:

```tsx
import React, { useRef, useState, useEffect } from "react";
import { View, Text, Button, StyleSheet } from "react-native";
import {
  ViroARSceneNavigator,
  ViroARScene,
  ViroText,
} from "@reactvision/react-viro";
import type { ViroFrameEvent } from "@reactvision/react-viro";

function TestARScene() {
  return (
    <ViroARScene>
      <ViroText
        text="Frame Streaming Test"
        position={[0, 0, -2]}
        style={{ fontSize: 30, color: "#ffffff" }}
      />
    </ViroARScene>
  );
}

export default function FrameStreamingTest() {
  const navigatorRef = useRef<any>(null);
  const [isStreaming, setIsStreaming] = useState(false);
  const [frameCount, setFrameCount] = useState(0);
  const [lastFrame, setLastFrame] = useState<{
    frameId: string;
    width: number;
    height: number;
    trackingState: string;
    dataSize: number;
  } | null>(null);

  const handleFrameUpdate = (event: ViroFrameEvent) => {
    setFrameCount((c) => c + 1);
    setLastFrame({
      frameId: event.frameId,
      width: event.width,
      height: event.height,
      trackingState: event.trackingState,
      dataSize: event.imageData.length,
    });
  };

  const toggleStreaming = () => {
    if (!navigatorRef.current) return;

    // Access the internal methods
    const nav = navigatorRef.current;

    if (isStreaming) {
      nav._stopFrameStream();
      setIsStreaming(false);
    } else {
      nav._startFrameStream({
        enabled: true,
        width: 640,
        height: 480,
        fps: 5,
        quality: 0.7,
      });
      setIsStreaming(true);
      setFrameCount(0);
    }
  };

  const testResolveDetection = async () => {
    if (!navigatorRef.current || !lastFrame) {
      console.log("No frame available to test");
      return;
    }

    const nav = navigatorRef.current;

    // Test resolving center point of the image
    const testPoints = [
      { x: 0.5, y: 0.5 },  // Center
      { x: 0.25, y: 0.25 }, // Top-left quadrant
      { x: 0.75, y: 0.75 }, // Bottom-right quadrant
    ];

    try {
      const result = await nav._resolveDetections(lastFrame.frameId, testPoints);
      console.log("=== Resolution Test Results ===");
      console.log(`Frame ID: ${result.frameId}`);

      result.results.forEach((r: any, i: number) => {
        console.log(`Point ${i} (${testPoints[i].x}, ${testPoints[i].y}):`);
        if (r.ok) {
          console.log(`  Position: [${r.worldPos.map((n: number) => n.toFixed(3)).join(", ")}]`);
          console.log(`  Method: ${r.method}`);
          console.log(`  Confidence: ${r.confidence.toFixed(2)}`);
        } else {
          console.log(`  Failed: ${r.error}`);
        }
      });
    } catch (error) {
      console.error("Resolution test failed:", error);
    }
  };

  return (
    <View style={styles.container}>
      <ViroARSceneNavigator
        ref={navigatorRef}
        initialScene={{ scene: TestARScene }}
        onFrameUpdate={handleFrameUpdate}
        style={styles.arView}
      />

      <View style={styles.overlay}>
        <Text style={styles.title}>Frame Streaming Test</Text>

        <View style={styles.stats}>
          <Text style={styles.stat}>
            Status: {isStreaming ? "Streaming" : "Stopped"}
          </Text>
          <Text style={styles.stat}>Frames: {frameCount}</Text>

          {lastFrame && (
            <>
              <Text style={styles.stat}>
                Size: {lastFrame.width}x{lastFrame.height}
              </Text>
              <Text style={styles.stat}>
                Tracking: {lastFrame.trackingState}
              </Text>
              <Text style={styles.stat}>
                Data: {(lastFrame.dataSize / 1024).toFixed(1)} KB
              </Text>
              <Text style={styles.stat} numberOfLines={1}>
                ID: {lastFrame.frameId}
              </Text>
            </>
          )}
        </View>

        <View style={styles.buttons}>
          <Button
            title={isStreaming ? "Stop Streaming" : "Start Streaming"}
            onPress={toggleStreaming}
          />
          <View style={{ height: 10 }} />
          <Button
            title="Test Detection Resolution"
            onPress={testResolveDetection}
            disabled={!lastFrame}
          />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  arView: {
    flex: 1,
  },
  overlay: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: "rgba(0, 0, 0, 0.7)",
    padding: 20,
  },
  title: {
    fontSize: 18,
    fontWeight: "bold",
    color: "#fff",
    marginBottom: 10,
  },
  stats: {
    marginBottom: 15,
  },
  stat: {
    color: "#fff",
    fontSize: 14,
    marginVertical: 2,
  },
  buttons: {
    marginTop: 10,
  },
});
```

### Expected Test Output

When running the test:

1. **Start Streaming**: Frame count should increase at ~5 FPS
2. **Frame Info**: Should show 640x480, tracking state "normal"
3. **Data Size**: JPEG should be ~20-50 KB at 0.7 quality
4. **Resolution Test**: Console should show world positions for test points

Example console output:
```
=== Resolution Test Results ===
Frame ID: 42_1234567890.123
Point 0 (0.5, 0.5):
  Position: [0.000, -0.150, -1.234]
  Method: raycast_geometry
  Confidence: 0.95
Point 1 (0.25, 0.25):
  Position: [-0.456, 0.123, -1.567]
  Method: lidar
  Confidence: 0.95
Point 2 (0.75, 0.75):
  Position: [0.234, -0.345, -0.890]
  Method: raycast_infinite
  Confidence: 0.85
```

## Performance Considerations

### Recommended Settings by Use Case

| Use Case | Resolution | FPS | Quality | Notes |
|----------|------------|-----|---------|-------|
| Gemini Live | 640x480 | 5 | 0.7 | Good balance |
| Low bandwidth | 320x240 | 2 | 0.5 | Minimal data |
| High accuracy | 1280x720 | 3 | 0.8 | Better detection |

### Memory Usage

- Ring buffer holds 30 frames by default
- Each frame stores: pose matrix, intrinsics, depth buffer (if LiDAR), feature points
- Feature points capped at 2000 to prevent memory issues

### Threading Model

- Frame capture runs on background queue (QOS_CLASS_USER_INITIATED)
- JPEG encoding is non-blocking
- `resolveDetections()` runs on background thread, returns on main thread

## Troubleshooting

### Frames Not Arriving

1. Check `trackingState` is "normal"
2. Verify `startFrameStream()` was called
3. Check console for `[ViroFrameStream]` log messages

### Resolution Always Fails

1. Ensure frame hasn't been evicted from ring buffer (30 frame limit)
2. Check that planes are detected in the AR scene
3. On non-LiDAR devices, raycast is the primary method

### High Latency

1. Reduce resolution (320x240 instead of 640x480)
2. Lower FPS (2-3 instead of 5)
3. Reduce JPEG quality (0.5 instead of 0.7)

## API Reference

### ViroFrameStreamConfig

```typescript
interface ViroFrameStreamConfig {
  enabled: boolean;   // Enable/disable streaming
  width: number;      // Target width (e.g., 640)
  height: number;     // Target height (e.g., 480)
  fps: number;        // Frames per second (1-5)
  quality: number;    // JPEG quality (0.0-1.0)
}
```

### ViroDetectionResolutionResult

```typescript
interface ViroDetectionResolutionResult {
  frameId: string;
  results: Array<{
    input: { x: number; y: number };
    ok: boolean;
    worldPos?: [number, number, number];
    confidence?: number;
    method?: "lidar" | "raycast_geometry" | "raycast_infinite" | "raycast_estimated" | "pointcloud";
    error?: string;
  }>;
  error?: string;
}
```

### Methods

| Method | Description |
|--------|-------------|
| `startFrameStream(config)` | Start streaming frames with given config |
| `stopFrameStream()` | Stop streaming frames |
| `resolveDetections(frameId, points)` | Resolve 2D points to 3D using capture-time data |

### Props

| Prop | Type | Description |
|------|------|-------------|
| `onFrameUpdate` | `(event: ViroFrameEvent) => void` | Callback for each captured frame |
