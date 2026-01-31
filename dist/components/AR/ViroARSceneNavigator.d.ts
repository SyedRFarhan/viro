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
import { ViroCloudAnchorProvider, ViroCloudAnchorStateChangeEvent, ViroGeospatialAnchorProvider, ViroFrameEvent } from "../Types/ViroEvents";
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
     * Trigger a depth-based scan wave effect on the camera background.
     * Set to true to trigger; the native side auto-completes the animation.
     * Set back to false after completion to allow re-triggering.
     * Requires depth data (LiDAR or monocular depth).
     * @default false
     */
    scanWaveEnabled?: boolean;
    /**
     * Configuration for the scan wave effect. All fields optional with sensible defaults.
     */
    scanWaveConfig?: ViroScanWaveConfig;
    /**
     * Enable cloud anchors for cross-platform anchor sharing.
     * When set to 'arcore', the ARCore Cloud Anchors SDK will be used.
     * Requires a valid Google Cloud API key configured in the native project.
     *
     * @default "none"
     * @platform ios,android
     */
    cloudAnchorProvider?: ViroCloudAnchorProvider;
    /**
     * Callback fired when a cloud anchor state changes.
     * This includes progress updates during hosting/resolving operations.
     */
    onCloudAnchorStateChange?: (event: ViroCloudAnchorStateChangeEvent) => void;
    /**
     * Enable the ARCore Geospatial API for location-based AR experiences.
     * When set to 'arcore', the ARCore Geospatial SDK will be used.
     * Requires a valid Google Cloud API key configured in the native project.
     *
     * @default "none"
     * @platform ios,android
     */
    geospatialAnchorProvider?: ViroGeospatialAnchorProvider;
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
