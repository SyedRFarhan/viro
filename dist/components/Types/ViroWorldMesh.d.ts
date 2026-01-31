/**
 * Copyright (c) 2024-present, Viro Media, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
/**
 * Configuration for world mesh generation and physics properties.
 */
export type ViroWorldMeshConfig = {
    /**
     * Sample every Nth pixel from the depth image.
     * Lower values = more detail but higher cost.
     * @default 4
     */
    stride?: number;
    /**
     * Minimum confidence threshold for depth samples (0.0-1.0).
     * Samples below this threshold are excluded from the mesh.
     * @default 0.3
     */
    minConfidence?: number;
    /**
     * Maximum depth distance in meters.
     * Samples beyond this distance are excluded from the mesh.
     * @default 5.0
     */
    maxDepth?: number;
    /**
     * Minimum time between mesh updates in milliseconds.
     * @default 100
     */
    updateIntervalMs?: number;
    /**
     * Time to keep the mesh after depth data is lost, in milliseconds.
     * After this time, the mesh is marked as stale.
     * @default 500
     */
    meshPersistenceMs?: number;
    /**
     * Friction coefficient for the physics surface (0.0-1.0).
     * Higher values = more friction.
     * @default 0.5
     */
    friction?: number;
    /**
     * Restitution (bounciness) of the physics surface (0.0-1.0).
     * 0 = no bounce, 1 = full bounce.
     * @default 0.3
     */
    restitution?: number;
    /**
     * Tag used to identify world mesh collisions in onCollision events.
     * @default "world"
     */
    collisionTag?: string;
    /**
     * Enable wireframe visualization of the depth mesh.
     * Useful for debugging and understanding the collision surface.
     * @default false
     */
    debugDrawEnabled?: boolean;
};
/**
 * Statistics about the current world mesh state.
 */
export type ViroWorldMeshStats = {
    /**
     * Number of vertices in the current mesh.
     */
    vertexCount: number;
    /**
     * Number of triangles in the current mesh.
     */
    triangleCount: number;
    /**
     * Average confidence of depth samples used to generate the mesh (0.0-1.0).
     */
    averageConfidence: number;
    /**
     * Timestamp of the last mesh update in milliseconds.
     */
    lastUpdateTimeMs: number;
    /**
     * True if depth data hasn't been received recently and the mesh may be outdated.
     */
    isStale: boolean;
};
/**
 * Event fired when the world mesh is updated.
 */
export type ViroWorldMeshUpdatedEvent = {
    /**
     * Current mesh statistics.
     */
    stats: ViroWorldMeshStats;
};
/**
 * On-demand snapshot of the current world mesh data.
 * [iOS Only]
 *
 * Note: With ARMeshAnchor integration, mesh data is delivered incrementally
 * through onAnchorFound/Updated/Removed events. This snapshot type is retained
 * for the imperative API but currently returns success: false.
 * Use ARMeshAnchor events for real-time mesh access.
 */
export type ViroWorldMeshSnapshot = {
    /**
     * Whether the snapshot was successfully captured.
     */
    success: boolean;
    /**
     * Number of vertices in the snapshot.
     */
    vertexCount?: number;
    /**
     * Number of triangles in the snapshot.
     */
    triangleCount?: number;
    /**
     * Base64-encoded Float32 array of vertex positions.
     * Layout: [x0, y0, z0, x1, y1, z1, ...]
     */
    verticesBase64?: string;
    /**
     * Base64-encoded Int32 array of triangle face indices.
     * Layout: [i0, i1, i2, ...] (3 per triangle)
     */
    indicesBase64?: string;
    /**
     * Base64-encoded Float32 array of per-vertex confidence values (0.0-1.0).
     */
    confidenceBase64?: string;
    /**
     * Error message if success is false.
     */
    error?: string;
};
/**
 * ARMeshClassification values from ARKit (iOS 13.4+).
 * These map to per-face classifications provided by LiDAR scene reconstruction.
 */
export declare enum ViroMeshClassification {
    None = 0,
    Wall = 1,
    Floor = 2,
    Ceiling = 3,
    Table = 4,
    Seat = 5,
    Window = 6,
    Door = 7
}
/**
 * Represents a mesh chunk from ARKit's ARMeshAnchor (iOS 13.4+, LiDAR devices).
 * Delivered through onAnchorFound/Updated/Removed with type="mesh".
 *
 * Geometry data is base64-encoded for efficient transfer across the bridge:
 * - verticesBase64: Float32Array (3 floats per vertex, anchor-local coords)
 * - indicesBase64: Int32Array (3 ints per triangle)
 * - normalsBase64: Float32Array (3 floats per vertex)
 * - classificationsBase64: Int32Array (1 int per face, ViroMeshClassification)
 */
export type ViroMeshAnchor = {
    /** Anchor type identifier - always "mesh" for mesh anchors. */
    type: 'mesh';
    /** Unique anchor identifier (UUID string). */
    anchorId: string;
    /** Anchor position in world coordinates. */
    position: [number, number, number];
    /** Anchor rotation in degrees (Euler angles). */
    rotation: [number, number, number];
    /** Anchor scale. */
    scale: [number, number, number];
    /** Number of vertices in this mesh chunk. */
    vertexCount: number;
    /** Number of triangular faces in this mesh chunk. */
    faceCount: number;
    /**
     * Base64-encoded Float32 array of vertex positions.
     * Layout: [x0, y0, z0, x1, y1, z1, ...] in anchor-local coordinates.
     * Decode with: new Float32Array(base64ToArrayBuffer(verticesBase64))
     */
    verticesBase64: string;
    /**
     * Base64-encoded Int32 array of triangle face indices.
     * Layout: [i0, i1, i2, i3, i4, i5, ...] (3 indices per triangle).
     */
    indicesBase64: string;
    /**
     * Base64-encoded Float32 array of per-vertex normals.
     * Layout: [nx0, ny0, nz0, nx1, ny1, nz1, ...].
     */
    normalsBase64: string;
    /**
     * Base64-encoded Int32 array of per-face classifications.
     * One ViroMeshClassification value per triangle.
     */
    classificationsBase64: string;
};
