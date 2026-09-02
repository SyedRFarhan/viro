//
//  VRODetectionResolver.h
//  ViroReact
//
//  Resolves 2D detection points to 3D world coordinates using capture-time data.
//  Uses a fallback ladder: LiDAR → raycast_geometry → mono (on demand) →
//  raycast_infinite → raycast_estimated → pointcloud.
//
//  Copyright © 2024 Viro Media. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <simd/simd.h>

@class VROFrameEntry;
@class ARSession;

NS_ASSUME_NONNULL_BEGIN

/**
 * VRODetectionResult represents the result of resolving a single 2D point to 3D.
 */
@interface VRODetectionResult : NSObject

/// Input point (normalized 0-1 UV in JPEG space)
@property (nonatomic, assign) float inputX;
@property (nonatomic, assign) float inputY;

/// Whether resolution succeeded
@property (nonatomic, assign) BOOL ok;

/// World position (valid if ok == YES)
@property (nonatomic, assign) simd_float3 worldPos;

/// Confidence level (0-1, varies by method)
/// - lidar: 0.95
/// - raycast_geometry: 0.95
/// - mono: 0.7
/// - raycast_infinite: 0.85
/// - raycast_estimated: 0.6
/// - pointcloud: 0.3-0.6 (decreases with distance)
@property (nonatomic, assign) float confidence;

/// Resolution method used
/// One of: "lidar", "raycast_geometry", "mono", "raycast_infinite", "raycast_estimated", "pointcloud"
@property (nonatomic, copy, nullable) NSString *method;

/// Error message if resolution failed (ok == NO)
@property (nonatomic, copy, nullable) NSString *error;

/// The world-space ray through this pixel at capture pose. Present on EVERY
/// result (fork >= 2.61.72): an unresolved point leaves the ledger a ray to
/// triangulate against a later sighting, and a resolved position lets JS
/// verify it lies on the ray.
@property (nonatomic, assign) BOOL hasRay;
@property (nonatomic, assign) simd_float3 rayOrigin;
@property (nonatomic, assign) simd_float3 rayDirection;

/// How many guessed rungs (infinite/estimated plane, point cloud) were
/// refused because they disagreed with the monocular depth at this pixel.
/// 0 when mono was unavailable or every rung agreed.
@property (nonatomic, assign) int gated;

@end


/**
 * On-demand monocular depth. Given the frame's upright JPEG (portrait when
 * rotatedToPortrait), returns metric depth in meters at model resolution as
 * packed row-major float32 with its dimensions, or nil when unavailable.
 * Runs the model synchronously; called at most once per frame entry.
 */
typedef NSData * _Nullable (^VROMonoDepthProvider)(CIImage *image, int *outWidth, int *outHeight);

/**
 * VRODetectionResolver resolves 2D detection points to 3D world coordinates
 * using capture-time data stored in VROFrameEntry.
 *
 * Resolution Methods (in order of preference):
 * 1. LiDAR depth sampling - most accurate on Pro devices
 * 2. Raycast against existing plane geometry - a measured surface, never gated
 * 3. Raycast against existing plane extended to infinity   ┐ each accepted only
 * 4. Raycast against estimated planes - can shift over time │ when monocular depth
 * 5. Feature point cloud fallback - nearest point to ray    ┘ (if present) agrees
 * 6. Monocular depth, estimated on demand from the captured frame - the
 *    off-plane case, or every guess refused by the gate
 *
 * CRITICAL: Uses capture-time pose/intrinsics from VROFrameEntry, NOT current frame.
 * This allows accurate resolution even when camera has moved since capture.
 */
@interface VRODetectionResolver : NSObject

/**
 * Resolve an array of 2D points to 3D world coordinates.
 *
 * @param points Array of dictionaries with "x" and "y" keys (normalized 0-1 UV)
 * @param entry Frame entry containing capture-time data
 * @param session Current AR session (for raycasting)
 * @return Array of VRODetectionResult objects
 */
+ (NSArray<VRODetectionResult *> *)resolvePoints:(NSArray<NSDictionary *> *)points
                                      frameEntry:(VROFrameEntry *)entry
                                       arSession:(ARSession *)session;

/**
 * Same, with an on-demand monocular depth provider. Pass nil to resolve
 * without the mono rung (identical to the three-argument form).
 */
+ (NSArray<VRODetectionResult *> *)resolvePoints:(NSArray<NSDictionary *> *)points
                                      frameEntry:(VROFrameEntry *)entry
                                       arSession:(ARSession *)session
                               monoDepthProvider:(nullable VROMonoDepthProvider)monoDepth;

/**
 * Same, with options:
 *  - "monoDepthCrop" (BOOL): run the mono model on a square crop around the
 *    point's detection box (each point may carry "box": [xmin, ymin, xmax,
 *    ymax] in the same UV space as x/y) instead of the squashed full frame.
 *    Capped at a few crops per frame; beyond that the full-frame map is used.
 */
+ (NSArray<VRODetectionResult *> *)resolvePoints:(NSArray<NSDictionary *> *)points
                                      frameEntry:(VROFrameEntry *)entry
                                       arSession:(ARSession *)session
                               monoDepthProvider:(nullable VROMonoDepthProvider)monoDepth
                                         options:(nullable NSDictionary *)options;

@end

NS_ASSUME_NONNULL_END
