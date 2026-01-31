/**
 * Copyright (c) 2024-present, Viro Media, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import { ViroWorldMeshSnapshot } from "./ViroWorldMesh";

/**
 * Error codes for world map persistence operations.
 * [iOS Only]
 */
export type ViroWorldMapErrorCode =
  | "NOT_FOUND" // File doesn't exist
  | "NOT_SUPPORTED" // Android (iOS only feature)
  | "DECODE_FAILED" // Corrupt or incompatible file
  | "SESSION_UNAVAILABLE" // AR session not ready
  | "BUSY" // Another operation in progress
  | "WORLD_MAP_NOT_READY"; // Tracking insufficient to save

/**
 * Result of a saveWorldMap() call.
 * [iOS Only]
 */
export type ViroSaveWorldMapResult = {
  /**
   * Whether the save operation succeeded.
   */
  success: boolean;

  /**
   * Error message if success is false.
   */
  error?: string;

  /**
   * Structured error code for programmatic handling.
   */
  code?: ViroWorldMapErrorCode;

  /**
   * Absolute path to the saved .arworldmap file.
   * Only present when success is true.
   *
   * Use this to upload the world map to your own cloud storage:
   * ```tsx
   * const result = await arRef.current?.saveWorldMap("my-session");
   * if (result?.success && result.filePath) {
   *   const data = await RNFS.readFile(result.filePath, 'base64');
   *   await uploadToCloud(data);
   * }
   * ```
   */
  filePath?: string;
};

/**
 * Result of a loadWorldMap() call.
 * [iOS Only]
 *
 * Note: success: true means the session was restarted with initialWorldMap set.
 * It does NOT guarantee relocalization will succeed - tracking can remain
 * .limited(.relocalizing) indefinitely if the environment has changed.
 */
export type ViroLoadWorldMapResult = {
  /**
   * Whether the load operation succeeded (session restarted with world map).
   */
  success: boolean;

  /**
   * Error message if success is false.
   */
  error?: string;

  /**
   * Structured error code for programmatic handling.
   */
  code?: ViroWorldMapErrorCode;
};

/**
 * Result of a deleteWorldMap() call.
 * [iOS Only]
 */
export type ViroDeleteWorldMapResult = {
  /**
   * Whether the delete operation succeeded.
   */
  success: boolean;

  /**
   * Error message if success is false.
   */
  error?: string;

  /**
   * Structured error code for programmatic handling.
   */
  code?: ViroWorldMapErrorCode;
};

/**
 * World mapping status values from ARKit.
 * [iOS Only]
 *
 * - notAvailable: Not enough data collected yet
 * - limited: Some data collected, but not reliable for saving
 * - extending: Good amount of data, actively improving (safe to save)
 * - mapped: Excellent coverage, stable (safe to save)
 */
export type ViroWorldMappingStatus =
  | "notAvailable"
  | "limited"
  | "extending"
  | "mapped";

/**
 * Tracking state values from ARKit.
 * [iOS Only]
 */
export type ViroTrackingStateValue = "notAvailable" | "limited" | "normal";

/**
 * Result of a getWorldMappingStatus() call.
 * [iOS Only]
 *
 * Use this to show scanning progress UI and determine when it's safe to save.
 */
export type ViroWorldMappingStatusResult = {
  /**
   * Current world mapping status.
   * Save is allowed when this is "extending" or "mapped".
   */
  mappingStatus: ViroWorldMappingStatus;

  /**
   * Current tracking state.
   * Save requires "normal" tracking.
   */
  trackingState: ViroTrackingStateValue;

  /**
   * Convenience boolean: true when both conditions for saving are met.
   * (trackingState === "normal" AND mappingStatus is "extending" or "mapped")
   */
  canSave: boolean;
};

/**
 * Event fired when world mapping status changes.
 * [iOS Only]
 *
 * This is more efficient than polling getWorldMappingStatus() as it only
 * fires when the status actually changes.
 *
 * @example
 * ```tsx
 * <ViroARSceneNavigator
 *   onWorldMappingStatusChanged={(event) => {
 *     console.log('Mapping:', event.mappingStatus, 'Can save:', event.canSave);
 *   }}
 * />
 * ```
 */
export type ViroWorldMappingStatusChangedEvent = ViroWorldMappingStatusResult;

/**
 * Imperative handle for ViroARSceneNavigator ref.
 * Provides direct access to world map persistence methods.
 * [iOS Only for world map methods]
 *
 * @example
 * ```tsx
 * const ref = useRef<ViroARSceneNavigatorHandle>(null);
 *
 * <ViroARSceneNavigator ref={ref} ... />
 *
 * // Save world map
 * const result = await ref.current?.saveWorldMap("my-session");
 * if (result?.success) {
 *   console.log("Saved!");
 * }
 *
 * // Load world map (restarts AR session)
 * await ref.current?.loadWorldMap("my-session");
 * ```
 */
export interface ViroARSceneNavigatorHandle {
  /**
   * Save the current world map to persistent storage.
   * [iOS Only]
   *
   * @param sessionId - Unique identifier for the session (used as filename if filePath not provided)
   * @param filePath - Optional custom path to save the world map. If omitted, saves to default cache location.
   * @returns Promise resolving to save result with success/error/code and the filePath where saved
   *
   * Requirements:
   * - Tracking state must be `.normal`
   * - World mapping status must be `.mapped` or `.extending`
   *
   * @example
   * ```tsx
   * // Save to default location
   * const result = await ref.current?.saveWorldMap("my-session");
   * console.log(result.filePath); // ~/Library/Caches/ViroARWorldMaps/my-session.arworldmap
   *
   * // Save to custom location
   * await ref.current?.saveWorldMap("backup", RNFS.DocumentDirectoryPath + '/backup.arworldmap');
   * ```
   *
   * On Android, returns { success: false, code: "NOT_SUPPORTED" }
   */
  saveWorldMap(
    sessionId: string,
    filePath?: string
  ): Promise<ViroSaveWorldMapResult>;

  /**
   * Load a previously saved world map and restart the AR session.
   * [iOS Only]
   *
   * @param sessionId - Unique identifier for the session to load
   * @param filePath - Optional custom path to load from. If omitted, loads from default cache location.
   * @returns Promise resolving to load result with success/error/code
   *
   * Important: success: true means the session was restarted with the world map.
   * Relocalization happens asynchronously - monitor ARFrame.camera.trackingState
   * for `.normal` to know when relocalization completes.
   *
   * @example
   * ```tsx
   * // Load from default location
   * await ref.current?.loadWorldMap("my-session");
   *
   * // Load from custom path (e.g., downloaded from cloud)
   * const tempPath = RNFS.TemporaryDirectoryPath + '/downloaded.arworldmap';
   * await RNFS.writeFile(tempPath, base64Data, 'base64');
   * await ref.current?.loadWorldMap("cloud-session", tempPath);
   * ```
   *
   * On Android, returns { success: false, code: "NOT_SUPPORTED" }
   */
  loadWorldMap(
    sessionId: string,
    filePath?: string
  ): Promise<ViroLoadWorldMapResult>;

  /**
   * Delete a previously saved world map from storage.
   * [iOS Only]
   *
   * @param sessionId - Unique identifier for the session to delete
   * @returns Promise resolving to delete result with success/error/code
   *
   * On Android, returns { success: false, code: "NOT_SUPPORTED" }
   */
  deleteWorldMap(sessionId: string): Promise<ViroDeleteWorldMapResult>;

  /**
   * Get the current world mapping status.
   * [iOS Only]
   *
   * Use this to check if the world map is ready to save, or to show
   * scanning progress UI. For continuous updates, use the
   * onWorldMappingStatusChanged prop instead.
   *
   * @returns Promise resolving to current mapping status, tracking state, and canSave flag
   *
   * On Android, returns { mappingStatus: "notAvailable", trackingState: "notAvailable", canSave: false }
   */
  getWorldMappingStatus(): Promise<ViroWorldMappingStatusResult>;

  /**
   * Capture an on-demand snapshot of the current world mesh data.
   * Returns base64-encoded binary arrays for compact serialization.
   * [iOS Only]
   *
   * @returns Promise resolving to mesh snapshot with base64-encoded vertex/index/confidence data
   *
   * @example
   * ```tsx
   * const snapshot = await ref.current?.getWorldMeshSnapshot();
   * if (snapshot?.success) {
   *   // Decode vertices: Float32Array with xyz per vertex
   *   const vertices = decodeBase64ToFloat32(snapshot.verticesBase64!);
   *   console.log(`${snapshot.vertexCount} vertices, ${snapshot.triangleCount} triangles`);
   * }
   * ```
   */
  getWorldMeshSnapshot(): Promise<ViroWorldMeshSnapshot>;
}

// =============================================================================
// DEPRECATED TYPES - Kept for backward compatibility, will be removed in future
// =============================================================================

/**
 * @deprecated Use the imperative ref API instead (saveWorldMap/loadWorldMap).
 * Status of world map persistence operations.
 * [iOS Only]
 */
export type ViroWorldMapPersistenceStatus =
  | "saving"
  | "saved"
  | "loading"
  | "loaded"
  | "error"
  | "notAvailable";

/**
 * @deprecated Use the imperative ref API instead (saveWorldMap/loadWorldMap).
 * Event fired when world map persistence status changes.
 * [iOS Only]
 */
export type ViroWorldMapPersistenceEvent = {
  /**
   * Current status of the persistence operation.
   */
  status: ViroWorldMapPersistenceStatus;

  /**
   * The session ID associated with this event.
   */
  sessionId: string;

  /**
   * Error message if status is "error".
   */
  error?: string;
};
