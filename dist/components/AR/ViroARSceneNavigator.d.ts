/**
 * Copyright (c) 2017-present, Viro Media, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 * @providesModule ViroARSceneNavigator
 * @flow
 */
import * as React from "react";
import { ViewProps } from "react-native";
import { ViroProvider, ViroCloudAnchorStateChangeEvent, ViroFrameEvent } from "../Types/ViroEvents";
import { ViroWorldMeshConfig, ViroWorldMeshStats } from "../Types/ViroWorldMesh";
import { ViroARSceneNavigatorHandle, ViroWorldMappingStatusChangedEvent } from "../Types/ViroWorldMap";
/**
 * Occlusion mode determines how virtual content is occluded by real-world objects.
 */
export type ViroOcclusionMode = "disabled" | "depthBased" | "peopleOnly";
/**
 * Configuration for the depth-based scan wave effect.
 * All fields are optional with sensible defaults — the effect works with zero configuration.
 * Default palette: "Vision Pro cool pearl white" (near-white with slight blue tint).
 */
export type ViroScanWaveConfig = {
    /** Total animation duration in ms. Default: 1000 */
    duration?: number;
    /** Fraction of duration for sweep (rest is fade). Default: 0.7 */
    sweepFraction?: number;
    /** Max depth in meters. Default: 5.0 */
    maxDepth?: number;
    /** Core wavefront band width in meters. Default: 0.25 */
    coreBandWidth?: number;
    /** Core brightness (0-1). Default: 0.6 */
    coreIntensity?: number;
    /** Core color [r,g,b] (0-1). Default: [0.92, 0.97, 1.0] (cool pearl) */
    waveCoreColor?: [number, number, number];
    /** Halo width in meters (trails behind core). Default: 0.5 */
    haloWidth?: number;
    /** Halo brightness (0-1). Default: 0.25 */
    haloIntensity?: number;
    /** Halo color [r,g,b] (0-1). Default: [0.85, 0.93, 1.0] */
    waveHaloColor?: [number, number, number];
    /** Rim glow color [r,g,b] (0-1). Default: [0.8, 0.9, 1.0] */
    rimColor?: [number, number, number];
    /** Rim glow brightness (0-1). Default: 0.4 */
    rimIntensity?: number;
    /** Rim glow spread (0.5-8, higher = softer). Default: 3.0 */
    rimPower?: number;
    /** Depth edge sensitivity. Default: 0.03 */
    edgeThreshold?: number;
    /** Noise shimmer tint [r,g,b] (0-1). Default: [0.9, 0.95, 1.0] */
    noiseTint?: [number, number, number];
    /** Noise shimmer intensity (0-1). Default: 0.1 */
    noiseIntensity?: number;
    /** Noise spatial scale. Default: 80.0 */
    noiseScale?: number;
    /** Noise animation speed. Default: 3.0 */
    noiseSpeed?: number;
    /** How far behind the wavefront the rim afterglow persists (meters). Default: 0.5 */
    trailLength?: number;
    /** Minimum brightness multiplier on flat surfaces (0-1). 0 = edges only, 1 = no attenuation. Default: 0.15 */
    detailMin?: number;
    /** Tonemap exposure for additive contribution. Higher = brighter effect. Default: 1.5 */
    tonemapExposure?: number;
    /** Accent tint color at the leading edge [r,g,b] (0-1). Default: [0.55, 0.70, 1.0] */
    accentColor?: [number, number, number];
    /** Accent tint intensity (0-1). 0 = off. Default: 0.0 */
    accentIntensity?: number;
};
/** Pre-built scan wave configurations. */
export declare const SCAN_WAVE_PRESETS: {
    /** Default — luminous cool pearl white (Vision Pro style). Native defaults ARE this preset. */
    readonly visionProCoolPearl: ViroScanWaveConfig;
    /** Warm pearl — same structure, warm-shifted palette */
    readonly visionProWarmPearl: ViroScanWaveConfig;
    /** Minimal — reduced intensities for subtlety */
    readonly subtleMinimal: ViroScanWaveConfig;
};
/**
 * ViroARSceneNavigator with ref support for imperative world map persistence API.
 *
 * @example
 * ```tsx
 * const ref = useRef<ViroARSceneNavigatorHandle>(null);
 *
 * <ViroARSceneNavigator ref={ref} ... />
 *
 * // Save world map
 * await ref.current?.saveWorldMap("my-session");
 *
 * // Load world map (restarts AR session)
 * await ref.current?.loadWorldMap("my-session");
 *
 * // Delete world map
 * await ref.current?.deleteWorldMap("my-session");
 * ```
 */
export declare const ViroARSceneNavigator: React.ForwardRefExoticComponent<ViewProps & {
    /**
     * ViroARSceneNavigator uses "scene" objects like the following to
     * describe a scene.
     */
    initialScene: {
        /**
         * The React Class to render for this scene.
         */
        scene: () => React.JSX.Element;
    };
    initialSceneKey?: string;
    /**
     * Optional fallback rendered when this navigator is mounted on a Meta Quest
     * device (where AR is not supported). When omitted, a default message view
     * is rendered. Pass `null` to render nothing.
     */
    questFallback?: React.ReactNode;
    autofocus?: boolean;
    /**
     * iOS only props! Note: these props may change as the underlying platforms coalesce in features.
     */
    worldAlignment?: "Gravity" | "GravityAndHeading" | "Camera";
    videoQuality?: "High" | "Low";
    numberOfTrackedImages?: number;
    viroAppProps?: any;
    /**
     * Renderer settings that can be used to enable or disable various
     * renderer capabilities and algorithms.
     */
    hdrEnabled?: boolean;
    pbrEnabled?: boolean;
    bloomEnabled?: boolean;
    shadowsEnabled?: boolean;
    multisamplingEnabled?: boolean;
    /**
     * Enable AR occlusion so real-world objects properly hide virtual content.
     * Requires a device with depth sensing capability.
     *
     * @default "disabled"
     */
    occlusionMode?: ViroOcclusionMode;
    /**
     * Enables depth sensing without activating occlusion rendering.
     * Virtual objects will NOT be occluded by real-world surfaces, but depth data
     * will be available for hit tests (DepthPoint type) and distance measurement.
     *
     * If occlusionMode="depthBased" is also set, occlusionMode takes precedence.
     *
     * Android: requires ARCore Depth API support (ARCore 1.18+).
     * iOS: uses LiDAR on supported devices, monocular depth estimator as fallback.
     *
     * @default false
     */
    depthEnabled?: boolean;
    /**
     * [Debug] Enable depth debug visualization to see how the depth texture is being sampled.
     * When enabled, the camera background will show a color overlay representing depth values:
     * - Magenta = No depth data
     * - Red = Very close (0-1m)
     * - Yellow = Medium (1-3m)
     * - Green = Medium-far (3-5m)
     * - Cyan = Far (5-10m)
     * - Blue = Very far (10m+)
     *
     * @default false
     */
    depthDebugEnabled?: boolean;
    /**
     * Default configuration for the scan wave effect. All fields optional.
     * These defaults are applied when triggerScanWave() is called without config,
     * or merged under any config overrides passed to triggerScanWave().
     */
    scanWaveConfig?: ViroScanWaveConfig;
    /**
     * [iOS Only] Prefer monocular depth estimation over LiDAR.
     * Callback fired when the scan wave animation completes all loops.
     * Useful for re-enabling UI or chaining actions after the effect finishes.
     */
    onScanWaveComplete?: () => void;
    /**
     * Enable cloud anchors for cross-platform anchor sharing.
     * When set to 'arcore', the ARCore Cloud Anchors SDK will be used.
     * Requires a valid Google Cloud API key configured in the native project.
     *
     * @default false
     */
    /**
     * Enable semantic segmentation debug visualization. When enabled, the camera
     * background shows a color overlay for each real-world category (sky, building, tree,
     * road, sidewalk, terrain, structure, object, vehicle, person, water).
     * Requires `setSemanticModeEnabled(true)` to be called on the scene navigator first.
     *
     * @default false
     */
    semanticDebugEnabled?: boolean;
    /**
     * Confidence threshold (0.0–1.0) below which semantic labels are discarded (treated
     * as unlabeled = 0) before the texture is uploaded to the GPU. Higher values reduce
     * noise and boundary blinking at the cost of smaller labeled regions.
     *
     * Only used on Android (ARCore provides per-pixel confidence). On iOS, ARKit's
     * segmentation is already temporally smoothed by the OS.
     *
     * @default 0.0
     */
    semanticConfidenceThreshold?: number;
    /**
     * [iOS Only] Prefer monocular depth estimation over LiDAR.
     * When true, monocular depth will be used even on devices with LiDAR.
     *
     * Monocular depth is automatically used on non-LiDAR devices when depth-based
     * occlusion is enabled. This prop allows forcing monocular depth on LiDAR devices.
     *
     * Useful for:
     * - Consistency across all device types (same depth method)
     * - Testing/comparison purposes
     * - Extended range beyond LiDAR's ~5m limit
     *
     * Requires:
     * - iOS 14.0+
     * - Neural Engine (A12 Bionic or newer)
     * - DepthPro.mlmodelc bundled in ViroKit
     *
     * @default false
     * @platform ios
     */
    preferMonocularDepth?: boolean;
    /**
     * Calibration scale applied to monocular depth values before use in occlusion.
     * 1.0 (default) = no change. Use < 1.0 if the model overestimates distances
     * (virtual objects visible through real surfaces). Use > 1.0 if it underestimates.
     * Typical tuning range: 0.7 – 1.3.
     *
     * @default 1.0
     * @platform ios
     */
    monocularDepthScale?: number;
    /**
     * Maximum inference rate for monocular depth (default: 5).
     * Lower values reduce device heat. Thermal state automatically
     * overrides this downward: Fair→3fps, Serious→2fps, Critical→stopped.
     * 3fps is barely perceptible for occlusion; 5fps is very smooth.
     *
     * @default 5
     * @platform ios
     */
    monocularDepthTargetFPS?: number;
    /**
     * Use the front (selfie) camera as the AR session background.
     *
     * Requires the optional `@reactvision/react-viro-face-tracking` package to be
     * installed — it provides the native front-camera AR configuration and, on
     * iOS, declares TrueDepth usage. Without it, this prop has no effect.
     *
     * On iOS the package uses the front TrueDepth camera; on Android it uses
     * ARCore Augmented Faces mode. World tracking, plane detection, and LiDAR are
     * unavailable in this mode.
     *
     * For a plain selfie feed without face tracking (no TrueDepth), use
     * `ViroCameraTexture` with `cameraPosition="front"` instead.
     *
     * @default false
     * @platform ios, android
     */
    frontCameraEnabled?: boolean;
    /**
     * Cloud and geospatial anchor provider.
     * Set to `"reactvision"` (default) for the ReactVision backend,
     * `"arcore"` for Google Cloud Anchors, or `"none"` to disable.
     *
     * Replaces the old `cloudAnchorProvider` / `geospatialAnchorProvider` props,
     * which are now deprecated. Both providers are set to the same value.
     *
     * @default "reactvision"
     * @platform ios,android
     */
    provider?: ViroProvider;
    /**
     * Callback fired when a cloud anchor state changes.
     * This includes progress updates during hosting/resolving operations.
     */
    onCloudAnchorStateChange?: (event: ViroCloudAnchorStateChangeEvent) => void;
    /**
     * Enable world mesh for physics collision with real-world surfaces.
     * When enabled, virtual physics objects will collide with detected
     * real-world geometry (floors, walls, tables, etc.).
     *
     * Requires depth sensing capability:
     * - iOS: LiDAR scanner (iPhone 12 Pro+, iPad Pro 2020+)
     * - Android: ToF sensor or ARCore Depth API support
     *
     * @default false
     * @platform ios,android
     */
    worldMeshEnabled?: boolean;
    /**
     * Configuration for world mesh generation and physics properties.
     * Only used when worldMeshEnabled is true.
     */
    worldMeshConfig?: ViroWorldMeshConfig;
    /**
     * Callback fired when the world mesh is updated.
     * Provides statistics about the current mesh state.
     */
    onWorldMeshUpdated?: (stats: ViroWorldMeshStats) => void;
    /**
     * [iOS Only] Callback fired when the world mapping status changes.
     * Use this to show scanning progress UI and know when it's safe to save.
     * Fires only when the status actually changes (not every frame).
     *
     * @example
     * ```tsx
     * <ViroARSceneNavigator
     *   onWorldMappingStatusChanged={(event) => {
     *     console.log('Mapping:', event.mappingStatus, 'Can save:', event.canSave);
     *     if (event.canSave) {
     *       // Enable save button
     *     }
     *   }}
     * />
     * ```
     */
    onWorldMappingStatusChanged?: (event: ViroWorldMappingStatusChangedEvent) => void;
    /**
     * [iOS Only] Callback fired when a new AR frame is captured for streaming.
     * Use this to stream frames to external services like Gemini for vision AI.
     *
     * Note: Frame streaming must be started with startFrameStream() first.
     */
    onFrameUpdate?: (event: ViroFrameEvent) => void;
} & React.RefAttributes<ViroARSceneNavigatorHandle>>;
