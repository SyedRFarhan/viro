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
