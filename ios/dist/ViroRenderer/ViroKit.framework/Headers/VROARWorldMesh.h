//
//  VROARWorldMesh.h
//  ViroRenderer
//
//  Copyright © 2024 Viro Media. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#ifndef VROARWorldMesh_h
#define VROARWorldMesh_h

#include <memory>
#include <string>
#include <chrono>
#include <functional>
#include <map>
#include <unordered_map>
#include <set>
#include <mutex>
#include <cstdint>
#include "VROVector3f.h"
#include "VROMatrix4f.h"
// Full definition needed: the incremental coverage path takes
// VROARFrame::VROARMeshChunk by value in its signature.
#include "VROARFrame.h"

class VROARDepthMesh;
class VROPhysicsWorld;
class VROPhysicsShape;
class VROPencil;
class VROScene;
class VROGeometry;
class VRONode;
class VROMaterial;
class btRigidBody;
class btDefaultMotionState;

/**
 * Configuration for world mesh generation and physics properties.
 */
struct VROWorldMeshConfig {
    // Mesh generation settings
    int stride = 4;                     // Sample every Nth pixel (lower = more detail, higher cost)
    float minConfidence = 0.3f;         // Minimum confidence threshold (0.0-1.0)
    float maxDepth = 5.0f;              // Maximum depth in meters

    // Update settings
    double updateIntervalMs = 500.0;    // Minimum time between mesh updates
    double meshPersistenceMs = 500.0;   // Time to keep mesh after depth data lost

    // Physics properties
    float friction = 0.5f;              // Surface friction coefficient
    float restitution = 0.3f;           // Bounciness (0 = no bounce, 1 = full bounce)
    std::string collisionTag = "world"; // Tag for collision event identification
    int physicsMaxTriangles = 0;        // Stride-decimation triangle cap (0 = no limit). Leaves
                                        // large gaps — prefer physicsCellSize for collision.
    float physicsCellSize = 0.10f;      // Vertex-clustering cell size in meters (0 = disabled).
                                        // Groups nearby vertices into a single representative,
                                        // producing a gap-free simplified mesh. Max collision gap =
                                        // sqrt(3) * cellSize. 0.10m → catches objects >~8cm reliably.
                                        // Applied before physicsMaxTriangles (if both set).

    // Visualization
    bool debugDrawEnabled = false;         // Enable wireframe visualization of mesh
    bool debugDrawDepthTest = true;        // Depth-test wireframe against scene (occluded by real surfaces)
    int debugDrawMaxTriangles = 1000;      // Triangle cap for wireframe debug draw
    float debugDrawLineThickness = 0.001f; // Line thickness for wireframe (meters)

    // ─── Coverage visualization (Polycam-style scan skin) ────────────────
    // The live mesh rendered as REAL translucent geometry — GPU-resident
    // between rebuilds, unlike the per-frame pencil wireframe above —
    // shaded by surface orientation, with a reveal glow on newly captured
    // area and a subtle moving shimmer. Every styling parameter below is
    // read LIVE by shader uniform binders each frame: changing the config
    // at runtime restyles the skin with no geometry or material rebuild
    // (and therefore no native rebuild to tune the look from JS).
    bool coverageDrawEnabled = false;
    float coverageColorR = 0.42f;            // base skin color (cool blue-white)
    float coverageColorG = 0.78f;
    float coverageColorB = 1.0f;
    float coverageOpacity = 0.45f;           // skin translucency
    float coverageShadingStrength = 0.7f;    // 0 = flat paint, 1 = full hemisphere relief
    float coverageRevealColorR = 0.85f;      // glow color for freshly captured area
    float coverageRevealColorG = 1.0f;
    float coverageRevealColorB = 1.0f;
    float coverageRevealIntensity = 0.8f;    // 0 disables the reveal glow
    float coverageRevealDurationSec = 1.6f;  // glow decay time constant (seconds)
    float coverageShimmerIntensity = 0.12f;  // 0 disables the moving sheen
    float coverageShimmerSpeed = 1.6f;       // sheen animation speed (radians/sec)
    float coverageShimmerScale = 2.2f;       // sheen spatial frequency (1/meters)
    double coverageUpdateIntervalMs = 500.0; // geometry rebuild cadence
    int coverageMaxTriangles = 150000;       // stride-decimate the visual above this
    float coverageBirthCellSize = 0.15f;     // voxel size for newness tracking (meters)

    // Polycam's overlay reads as a triangulated RECONSTRUCTION, not a
    // smooth film — that texture comes from the three knobs below.
    bool coverageFlatShading = true;         // per-face normals: the faceted mosaic look
                                             // (false = smooth vertex normals, the v1 film)
    float coverageFacetJitter = 0.06f;       // per-face brightness variation (0 disables)
    float coverageEdgeIntensity = 0.35f;     // hairline triangle-edge lines (0 disables)
    float coverageEdgeColorR = 1.0f;         // edge line color
    float coverageEdgeColorG = 1.0f;
    float coverageEdgeColorB = 1.0f;
    float coverageBoundaryIntensity = 0.9f;  // glow at the mesh's OPEN boundary — the
                                             // growth frontier of the scan (0 disables)
    float coverageBoundaryColorR = 0.75f;    // frontier glow color
    float coverageBoundaryColorG = 0.95f;
    float coverageBoundaryColorB = 1.0f;
    float coverageBoundaryPulseSpeed = 2.6f; // frontier breathing rate (radians/sec; 0 = steady)
    float coverageBoundaryFill = 0.0f;       // 0 = thin rim at open edges (v1 look);
                                             // 1 = solid frontier patches (Polycam's blue fill)
    float coverageEdgeDash = 0.0f;           // 0 = solid hairline edges; >0 = dashed
                                             // wireframe, value = dashes per triangle edge
    float coverageEdgeWidth = 0.02f;         // wireframe line width, bary-space floor
                                             // (0.02 ≈ 1px; Polycam ≈ 0.035)
    float coverageRevealOpacityBoost = 0.5f; // how much the reveal RAISES alpha:
                                             // alpha = opacity*(1 + boost*reveal). High
                                             // values (4-8) make fresh mesh a solid
                                             // sheet that dissolves as it settles
    float coverageUnscannedColorR = 0.05f;   // tint over directions with NO mesh —
    float coverageUnscannedColorG = 0.08f;   // Polycam's "not scanned yet" dimming
    float coverageUnscannedColorB = 0.16f;
    float coverageUnscannedOpacity = 0.0f;   // 0 disables the unscanned tint entirely
    bool coverageFreezeOnDisable = false;    // keep the last coverage chunks rendered
                                             // (frozen) when the mesh is disabled —
                                             // pairs with turning ARKit scene
                                             // reconstruction off to save power
};

/**
 * Identifies the data source that produced a world mesh.
 */
enum class VROWorldMeshSource {
    LiDAR,      // ARKit ARMeshAnchor (LiDAR-equipped device)
    Monocular,  // Monocular depth estimation (non-LiDAR device)
    Plane,      // Triangulated AR plane anchors (fallback)
    Unknown
};

/**
 * Statistics about the current world mesh state.
 */
struct VROWorldMeshStats {
    int vertexCount = 0;                // Number of vertices in mesh
    int triangleCount = 0;              // Number of triangles in mesh
    float averageConfidence = 0.0f;     // Average confidence of depth samples
    double lastUpdateTimeMs = 0.0;      // Timestamp of last mesh update
    bool isStale = false;               // True if depth data hasn't been received recently
};

/**
 * Delivered to every registered subscriber when the world mesh is updated.
 */
struct VROWorldMeshUpdate {
    std::shared_ptr<VROARDepthMesh> mesh;
    VROWorldMeshStats stats;
    VROWorldMeshSource source = VROWorldMeshSource::Unknown;
};

/**
 * Per-subscriber options controlling mesh decimation.
 * maxTriangles = 0 means no limit (full mesh delivered as-is).
 */
struct VROWorldMeshSubscriberOptions {
    enum class DecimationStrategy {
        Stride,       // Take every N-th triangle (O(1) per triangle, default)
    };

    int maxTriangles = 0;                              // 0 = unlimited
    DecimationStrategy strategy = DecimationStrategy::Stride;
};

using VROWorldMeshSubscriberId = uint32_t;
using VROWorldMeshSubscriberCallback = std::function<void(const VROWorldMeshUpdate&)>;

/**
 * Legacy callback — delivers only stats. Kept for back-compat; prefer subscribe().
 */
using VROWorldMeshUpdateCallback = std::function<void(const VROWorldMeshStats&)>;

/**
 * Custom deleter for btRigidBody.
 * Bullet requires removing the body from the dynamics world before deletion;
 * this deleter encapsulates that invariant so it can't be forgotten.
 */
struct BulletRigidBodyDeleter {
    std::weak_ptr<VROPhysicsWorld> physicsWorld;
    void operator()(btRigidBody *body) const;
};

/**
 * VROARWorldMesh manages the lifecycle of a physics collision mesh generated
 * from AR depth data. It automatically updates the mesh from incoming AR frames
 * and maintains a Bullet physics body for collision detection.
 *
 * This enables virtual objects to physically interact with real-world surfaces
 * detected through depth sensing (LiDAR on iOS, ToF/ARCore Depth on Android).
 */
class VROARWorldMesh : public std::enable_shared_from_this<VROARWorldMesh> {
public:
    /**
     * Create a new world mesh manager.
     *
     * @param physicsWorld The physics world to add the collision body to
     */
    VROARWorldMesh(std::shared_ptr<VROPhysicsWorld> physicsWorld);
    ~VROARWorldMesh();

    /**
     * Update the world mesh from the current AR frame.
     * This should be called each frame. The mesh will only be regenerated
     * if enough time has passed since the last update (controlled by updateIntervalMs).
     *
     * @param frame The current AR frame with depth data
     */
    void updateFromFrame(const std::unique_ptr<VROARFrame>& frame);

    /**
     * Force an immediate mesh update, ignoring the update interval.
     *
     * @param frame The current AR frame with depth data
     */
    void forceUpdate(const std::unique_ptr<VROARFrame>& frame);

    /**
     * Set the mesh configuration. Changes take effect on next update.
     */
    void setConfig(const VROWorldMeshConfig& config);

    /**
     * Get the current configuration.
     */
    VROWorldMeshConfig getConfig() const { return _config; }

    /**
     * Enable or disable the world mesh.
     * When disabled, the mesh is removed from the physics world.
     */
    void setEnabled(bool enabled);

    /**
     * Check if the world mesh is enabled.
     */
    bool isEnabled() const { return _enabled; }

    /**
     * Get the current mesh data (may be nullptr if no mesh generated yet).
     */
    std::shared_ptr<VROARDepthMesh> getCurrentMesh() const { return _currentMesh; }

    /**
     * Get statistics about the current mesh state.
     */
    VROWorldMeshStats getStats() const;

    /**
     * Subscribe to mesh updates. Returns an opaque ID used to unsubscribe.
     * The callback is invoked on the render thread after each successful mesh build.
     * @param callback Receives the full VROWorldMeshUpdate (mesh, stats, source).
     * @param options  Per-consumer options (e.g. maxTriangles for W3 decimation).
     */
    VROWorldMeshSubscriberId subscribe(VROWorldMeshSubscriberCallback callback,
                                       VROWorldMeshSubscriberOptions options = {});

    /**
     * Unsubscribe a previously registered callback. No-op if id is not found.
     */
    void unsubscribe(VROWorldMeshSubscriberId id);

    /**
     * @deprecated Prefer subscribe(). Delivers stats only, no mesh data.
     */
    void setUpdateCallback(VROWorldMeshUpdateCallback callback) {
        _updateCallback = callback;
    }

    /**
     * Draw the mesh wireframe using the provided pencil.
     * Should be called each frame when debugDrawEnabled is true.
     *
     * @param pencil The pencil to use for drawing lines
     */
    void debugDraw(std::shared_ptr<VROPencil> pencil);

    /**
     * WS-C: serialize the current mesh (vertices, per-vertex confidences,
     * triangle indices) into a compact custom binary format for persisting
     * as a cloud anchor asset (see finishScan() and rvUploadAsset()).
     *
     * Not glTF: this format is only ever read back by loadMeshSnapshot() in
     * this same class, not by third-party tools, so a minimal custom layout
     * avoids the risk of an unvalidated hand-written glTF writer producing
     * spec-invalid files (this repo has no way to open the result in a
     * glTF viewer to confirm correctness).
     *
     * @param locationTransform The same anchor/location-frame transform used
     *        to host this scan (RVCCACloudAnchorProvider's anchorTransform or
     *        computeLocationTransform() result). Vertices are stored relative
     *        to this frame (world = locationTransform * local), NOT in this
     *        session's raw world space — a resolve on a different device has
     *        a different, unrelated world origin, so raw world-space vertices
     *        would be meaningless there. This mirrors how SIFT features are
     *        already stored anchor/location-local (FeatureExtractor::toLocal).
     *
     * Layout (little-endian, matches all current target architectures):
     *   [0:4)   magic "RVWM"
     *   [4:5)   format version (1)
     *   [5:9)   vertexCount   (uint32)
     *   [9:13)  triangleCount (uint32)
     *   vertices:    vertexCount   * 3 * float32 (x,y,z, relative to locationTransform)
     *   confidences: vertexCount   * float32
     *   indices:     triangleCount * 3 * int32
     *
     * @return Empty vector if there is no current mesh.
     */
    std::vector<uint8_t> serializeCurrentMesh(const VROMatrix4f& locationTransform) const;

    /**
     * WS-C: reconstruct a VROARDepthMesh from bytes produced by
     * serializeCurrentMesh(), transforming vertices from the stored
     * location-frame-relative space into this session's world space.
     *
     * @param resolvedTransform The transform resolveCloudAnchor() computed
     *        for this session (the resolved anchor's world transform) —
     *        the same role locationTransform played at host time, now
     *        mapping local -> this session's world instead of the reverse.
     * @return nullptr if data is malformed (bad magic/version, truncated).
     */
    static std::shared_ptr<VROARDepthMesh> loadMeshSnapshot(const std::vector<uint8_t>& data,
                                                             const VROMatrix4f& resolvedTransform);

    /**
     * WS-C: attach a resolved (static) mesh snapshot loaded via
     * loadMeshSnapshot() — the counterpart to the live per-frame mesh for
     * mesh data recovered from a resolved cloud anchor's asset. Adds both:
     *   - Physics: reuses applyMeshToPhysics() verbatim, the same pipeline
     *     already used for the live mesh (clustering/decimation + async BVH).
     *   - Visual occlusion: builds a static, invisible depth-only geometry
     *     (see buildOcclusionGeometry()) and adds it to the scene root.
     *     This path is NEW engine code, verified only by compilation — this
     *     repo has no way to render an AR scene, so it has not been visually
     *     confirmed to occlude correctly. Test on device before shipping.
     *
     * @param mesh The resolved mesh, already in this session's world space
     *        (see loadMeshSnapshot()'s resolvedTransform parameter).
     * @param scene The scene to add the occlusion geometry node to.
     */
    void attachResolvedMesh(std::shared_ptr<VROARDepthMesh> mesh, std::shared_ptr<VROScene> scene);

    /**
     * WS-C: build a static, invisible depth-only VROGeometry from a mesh's
     * vertices/indices. The material writes to the depth buffer but not the
     * color buffer (VROColorMaskNone) and disables culling (the mesh's
     * winding was computed relative to a different session's camera, not
     * guaranteed consistent for this session's viewpoints) — so it never
     * appears itself but still correctly z-tests virtual content behind it.
     * Public for testability; normally called via attachResolvedMesh().
     *
     * @return nullptr if mesh is null/invalid/empty.
     */
    static std::shared_ptr<VROGeometry> buildOcclusionGeometry(std::shared_ptr<VROARDepthMesh> mesh);

    /**
     * Coverage skin: the scene whose root the coverage node attaches to.
     * Set by VROARScene when the world mesh is created; without it the
     * coverage visualization silently stays off.
     */
    void setCoverageScene(std::shared_ptr<VROScene> scene);

private:
    std::weak_ptr<VROPhysicsWorld> _physicsWorld;

    // Bullet physics components — smart pointers for exception-safe lifecycle.
    // BulletRigidBodyDeleter removes the body from the world before deletion.
    std::unique_ptr<btRigidBody, BulletRigidBodyDeleter> _rigidBody;
    std::unique_ptr<btDefaultMotionState> _motionState;
    std::shared_ptr<VROPhysicsShape> _physicsShape;

    // Current mesh data
    std::shared_ptr<VROARDepthMesh> _currentMesh;

    // Configuration and state
    VROWorldMeshConfig _config;
    bool _enabled = false;
    bool _isAddedToPhysicsWorld = false;  // guard against re-add on rapid updates

    // Timing
    double _lastUpdateTimeMs = 0.0;
    double _lastDepthTimeMs = 0.0;

    // Legacy stats-only callback
    VROWorldMeshUpdateCallback _updateCallback;

    // Subscriber registry
    std::map<VROWorldMeshSubscriberId,
             std::pair<VROWorldMeshSubscriberCallback, VROWorldMeshSubscriberOptions>> _subscribers;
    VROWorldMeshSubscriberId _nextSubscriberId = 1;
    mutable std::mutex _subscriberMutex;

    /**
     * Apply a new mesh to the physics world.
     * Creates a new physics shape and rigid body from the mesh.
     */
    void applyMeshToPhysics(std::shared_ptr<VROARDepthMesh> mesh);

    /**
     * Remove the current physics body from the world.
     */
    void removeFromPhysicsWorld();

    /**
     * Add the current physics body to the world.
     */
    void addToPhysicsWorld();

    /**
     * Get the current time in milliseconds.
     */
    double getCurrentTimeMs() const;

    /**
     * Check if enough time has passed for a new update.
     */
    bool shouldUpdate() const;

    /**
     * Check if the mesh is stale (depth data not received recently).
     */
    bool isMeshStale() const;

    /**
     * Fire the legacy _updateCallback and all registered subscribers.
     * Called on the render thread after a mesh is successfully applied.
     */
    void notifySubscribers(std::shared_ptr<VROARDepthMesh> mesh);

    // ─── Coverage skin (Polycam-style) ───────────────────────────────────
    std::weak_ptr<VROScene> _coverageScene;
    std::shared_ptr<VRONode> _coverageNode;
    std::shared_ptr<VROMaterial> _coverageMaterial;
    double _coverageStartMs = 0.0;        // uniform time base (float precision)
    double _lastCoverageBuildMs = 0.0;
    int _lastCoverageTriangles = -1;
    // Voxel cell → first-seen time (seconds since _coverageStartMs). Feeds
    // the per-vertex birth channel so the shader can glow fresh area.
    // Bounded by scanned volume (~a few thousand cells per room at 15cm).
    std::unordered_map<uint64_t, float> _cellBirthSec;

    // ── Incremental (per-anchor) coverage state ──
    // One child node per ARMeshAnchor; only anchors whose digest changed
    // rebuild. The edge registry counts triangle-uses of position-quantized
    // edges ACROSS anchors, so a chunk-border edge shared by two anchors
    // reads count 2 (interior) and only true open boundary reads 1.
    struct VROCoverageChunk {
        std::shared_ptr<VRONode> node;
        uint64_t digest = 0;
        std::vector<uint64_t> edges;   // one entry per triangle-use
    };
    std::map<std::string, VROCoverageChunk> _coverageChunks;
    std::unordered_map<uint64_t, int> _coverageEdgeUse;
    // Chunk ids kept as a FROZEN display after a freeze-on-disable: excluded
    // from removal when live anchors (new UUIDs) take over on re-enable.
    std::set<std::string> _frozenChunkIds;
    // The unscanned tint: an inside-out sphere drawn AFTER the chunks with
    // depth testing — mesh occludes it, so tint shows only where nothing
    // was scanned. Chunk-path (LiDAR) only; the sparse non-LiDAR fallback
    // meshes would leave the whole screen tinted.
    std::shared_ptr<VRONode> _coverageTintNode;
    std::shared_ptr<VROMaterial> _coverageTintMaterial;

    /** Create/update/remove the unscanned-tint sphere per config. */
    void ensureCoverageTint();

    /**
     * Route a fresh mesh update to the right coverage path: incremental
     * per-anchor chunks when the frame has them, whole-mesh fallback
     * otherwise; tears everything down when the feature is off.
     */
    void dispatchCoverageUpdate(const std::unique_ptr<VROARFrame>& frame,
                                std::shared_ptr<VROARDepthMesh> mergedMesh);

    /**
     * Rebuild the coverage skin from a freshly applied mesh, rate-limited
     * by coverageUpdateIntervalMs and skipped when the mesh is unchanged.
     * Fallback path for sources without per-anchor chunks (depth / plane).
     */
    void updateCoverageVisual(std::shared_ptr<VROARDepthMesh> mesh);

    /**
     * Incremental path: rebuild only anchors whose content digest changed
     * (plus neighbors whose open-boundary status those changes flipped),
     * drop nodes for removed anchors. This is what makes new area appear
     * the moment ARKit delivers it — no whole-mesh rebuild.
     */
    void updateCoverageVisualChunks(const std::vector<VROARFrame::VROARMeshChunk>& chunks);

    /** Remove every coverage node and clear all incremental state. */
    void teardownCoverage();

    /**
     * Build the visible coverage geometry: smooth per-vertex normals for
     * hemisphere shading, per-vertex birth time (seconds) in texcoord U
     * for the reveal glow. boundaryOverride, when given, supplies
     * per-vertex open-boundary flags computed against the cross-anchor
     * edge registry; without it, boundary is detected locally (weld).
     */
    std::shared_ptr<VROGeometry> buildCoverageGeometry(std::shared_ptr<VROARDepthMesh> mesh,
                                                       const std::vector<uint8_t>* boundaryOverride = nullptr);

    /**
     * Create the (single, reused) coverage material: translucent, unlit,
     * with a Surface shader modifier whose uniforms are bound to the live
     * config every frame — styling changes need no rebuild of anything.
     */
    std::shared_ptr<VROMaterial> createCoverageMaterial();

    /**
     * Return a decimated copy of mesh with at most maxTriangles triangles,
     * using Stride strategy (every N-th triangle). Vertices are copied as-is;
     * only the index buffer is thinned. Returns mesh unchanged if already within budget.
     */
    static std::shared_ptr<VROARDepthMesh> decimateMesh(
        std::shared_ptr<VROARDepthMesh> mesh, int maxTriangles);

    /**
     * Vertex-clustering simplification. Groups all vertices within cellSize metres
     * into a single representative, rebuilds triangles, drops degenerate ones.
     * Produces a gap-free mesh: max gap = sqrt(3)*cellSize.
     * 0.10m cells → catches objects wider than ~8cm reliably.
     */
    static std::shared_ptr<VROARDepthMesh> clusterMesh(
        std::shared_ptr<VROARDepthMesh> mesh, float cellSize);
};

#endif /* VROARWorldMesh_h */
