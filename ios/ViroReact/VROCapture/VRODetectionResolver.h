//
//  VRODetectionResolver.h
//  ViroReact
//
//  Resolves 2D detection points to 3D world coordinates using capture-time data.
//  Uses a fallback ladder: LiDAR → raycast_geometry → raycast_extent →
//  raycast_estimated → pointcloud.
//
//  Copyright © 2024 Viro Media. All rights reserved.
//

#import <Foundation/Foundation.h>
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
/// - raycast_extent: 0.85
/// - raycast_estimated: 0.6
/// - pointcloud: 0.3-0.6 (decreases with distance)
@property (nonatomic, assign) float confidence;

/// Resolution method used
/// One of: "lidar", "raycast_geometry", "raycast_extent", "raycast_estimated", "pointcloud"
@property (nonatomic, copy, nullable) NSString *method;

/// Error message if resolution failed (ok == NO)
@property (nonatomic, copy, nullable) NSString *error;

@end


/**
 * VRODetectionResolver resolves 2D detection points to 3D world coordinates
 * using capture-time data stored in VROFrameEntry.
 *
 * Resolution Methods (in order of preference):
 * 1. LiDAR depth sampling - most accurate on Pro devices
 * 2. Raycast against existing plane geometry - hits actual mesh
 * 3. Raycast against existing plane extent - hits bounding box
 * 4. Raycast against estimated planes - can shift over time
 * 5. Feature point cloud fallback - finds nearest point to ray
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

@end

NS_ASSUME_NONNULL_END
