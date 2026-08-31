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
    /**
     * Render the scan-coverage skin over captured surfaces.
     * @default false
     */
    coverageDrawEnabled?: boolean;
    /**
     * Base skin color as [r, g, b], each 0-1.
     * @default [0.42, 0.78, 1.0] (cool blue-white)
     */
    coverageColor?: [number, number, number];
    /**
     * Skin translucency (0 invisible - 1 solid).
     * @default 0.45
     */
    coverageOpacity?: number;
    /**
     * Hemisphere-relief shading strength: 0 = flat paint, 1 = full relief
     * (up-facing surfaces bright, sides mid, down-facing dim).
     * @default 0.7
     */
    coverageShadingStrength?: number;
    /**
     * Glow color for freshly captured area, [r, g, b] 0-1.
     * @default [0.85, 1.0, 1.0]
     */
    coverageRevealColor?: [number, number, number];
    /**
     * Reveal glow strength; 0 disables the reveal.
     * @default 0.8
     */
    coverageRevealIntensity?: number;
    /**
     * Reveal glow decay time constant in milliseconds.
     * @default 1600
     */
    coverageRevealDurationMs?: number;
    /**
     * Travelling sheen strength; 0 disables the shimmer.
     * @default 0.12
     */
    coverageShimmerIntensity?: number;
    /**
     * Sheen animation speed (radians/second).
     * @default 1.6
     */
    coverageShimmerSpeed?: number;
    /**
     * Sheen spatial frequency (1/meters).
     * @default 2.2
     */
    coverageShimmerScale?: number;
    /**
     * Minimum time between coverage geometry rebuilds (ms). Between
     * rebuilds the skin is a static GPU buffer.
     * @default 500
     */
    coverageUpdateIntervalMs?: number;
    /**
     * Stride-decimate the coverage visual above this triangle count.
     * @default 150000
     */
    coverageMaxTriangles?: number;
    /**
     * Voxel size (meters) for tracking which area is newly captured
     * (feeds the reveal glow).
     * @default 0.15
     */
    coverageBirthCellSize?: number;
    /**
     * Per-face flat shading: the faceted triangulated-mesh look (and what
     * the edge lines detect). false = smooth film. Note: flat shading
     * de-indexes the geometry (3 vertices/triangle) — consider a lower
     * coverageMaxTriangles.
     * @default true
     */
    coverageFlatShading?: boolean;
    /**
     * Per-face brightness variation (0 disables) — the subtle mosaic
     * tile-to-tile tone shift of a reconstruction overlay.
     * @default 0.06
     */
    coverageFacetJitter?: number;
    /**
     * Hairline triangle-edge line strength (0 disables). Only visible with
     * coverageFlatShading.
     * @default 0.35
     */
    coverageEdgeIntensity?: number;
    /**
     * Triangle-edge line color, [r, g, b] 0-1.
     * @default [1, 1, 1]
     */
    coverageEdgeColor?: [number, number, number];
    /**
     * Glow strength at the mesh's OPEN boundary — the scan's growth
     * frontier (0 disables).
     * @default 0.9
     */
    coverageBoundaryIntensity?: number;
    /**
     * Growth-frontier glow color, [r, g, b] 0-1.
     * @default [0.75, 0.95, 1.0]
     */
    coverageBoundaryColor?: [number, number, number];
    /**
     * Frontier glow breathing rate (radians/second; 0 = steady).
     * @default 2.6
     */
    coverageBoundaryPulseSpeed?: number;
    /**
     * Frontier rendering shape: 0 = thin rim hugging open edges, 1 = solid
     * patches over the whole frontier ring of triangles (Polycam's blue
     * fill). Interpolates between the two.
     * @default 0
     */
    coverageBoundaryFill?: number;
    /**
     * Edge line style: 0 = solid hairlines; >0 breaks them into a dashed
     * wireframe, value = dash frequency in 1/meters (try 8-14).
     * @default 0
     */
    coverageEdgeDash?: number;
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
 * through onAnchorFound/Updated/Removed events. This snapshot type provides
 * on-demand access to the current ARKit mesh state via the imperative API.
 *
 * @example
 * ```tsx
 * const snapshot = await ref.current?.getWorldMeshSnapshot({ includeGeometry: true });
 * if (snapshot?.success && snapshot.anchors) {
 *   for (const anchor of snapshot.anchors) {
 *     console.log(`Anchor ${anchor.anchorId}: ${anchor.vertexCount} verts`);
 *   }
 * }
 * ```
 */
export type ViroWorldMeshSnapshot = {
    /** Whether the snapshot was successfully captured. */
    success: boolean;
    /** Error message if success is false. */
    error?: string;
    /** Aggregate stats across all mesh anchors. */
    stats?: {
        anchorCount: number;
        totalVertexCount: number;
        totalFaceCount: number;
    };
    /**
     * Per-anchor mesh data. Only present when `includeGeometry: true` is passed.
     * Each anchor corresponds to an ARMeshAnchor from ARKit.
     */
    anchors?: Array<{
        anchorId: string;
        position: [number, number, number];
        /**
         * Full anchor transform, 16 floats COLUMN-MAJOR (simd's natural
         * flattening — same convention as ar_pose). Vertices are anchor-local;
         * world = transform * [x, y, z, 1]. Present from fork 2.61.64.
         */
        transform?: number[];
        vertexCount: number;
        faceCount: number;
        /** Base64-encoded Float32 array of vertex positions. */
        verticesBase64: string;
        /** Base64-encoded Int32 array of triangle face indices. */
        indicesBase64: string;
        /** Base64-encoded Float32 array of per-vertex normals. */
        normalsBase64: string;
        /** Base64-encoded Int32 array of per-face classification values. */
        classificationsBase64: string;
    }>;
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
