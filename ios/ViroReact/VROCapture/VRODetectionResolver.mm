//
//  VRODetectionResolver.mm
//  ViroReact
//
//  Implementation of 2D→3D detection resolution using capture-time data.
//
//  Copyright © 2024 Viro Media. All rights reserved.
//

#import "VRODetectionResolver.h"
#import "VROFrameRingBuffer.h"
#import <ARKit/ARKit.h>

#pragma mark - VRODetectionResult Implementation

@implementation VRODetectionResult
@end


#pragma mark - VRODetectionResolver Implementation

@implementation VRODetectionResolver

+ (NSArray<VRODetectionResult *> *)resolvePoints:(NSArray<NSDictionary *> *)points
                                      frameEntry:(VROFrameEntry *)entry
                                       arSession:(ARSession *)session {

    NSMutableArray<VRODetectionResult *> *results = [NSMutableArray arrayWithCapacity:points.count];

    for (NSDictionary *point in points) {
        float jpegU = [point[@"x"] floatValue];  // Normalized 0-1 in JPEG space
        float jpegV = [point[@"y"] floatValue];

        VRODetectionResult *result = [[VRODetectionResult alloc] init];
        result.inputX = jpegU;
        result.inputY = jpegV;
        result.ok = NO;

        // Try methods in order of preference

        // 1. LiDAR depth sampling (if available for this frame)
        //    CRITICAL: Must transform JPEG UV → AR UV using jpegToARTransform
        if (entry.depthBuffer) {
            simd_float3 worldPos;
            float confidence;
            if ([self sampleLiDARDepth:entry
                                jpegU:jpegU jpegV:jpegV
                             worldPos:&worldPos
                           confidence:&confidence]) {
                result.ok = YES;
                result.worldPos = worldPos;
                result.confidence = confidence;
                result.method = @"lidar";
                [results addObject:result];
                continue;
            }
        }

        // 2. Raycast against planes using capture-time camera
        //    IMPORTANT: Prefer existing planes first, then estimated
        simd_float3 rayOrigin, rayDirection;
        [self computeRayFromJpegUV:jpegU v:jpegV
                             entry:entry
                         rayOrigin:&rayOrigin
                      rayDirection:&rayDirection];

        if (@available(iOS 14.0, *)) {
            // Raycast target ladder (in order of preference/accuracy):
            // 1. ExistingPlaneGeometry - most accurate, actual mesh
            // 2. ExistingPlaneUsingExtent - plane bounding box
            // 3. EstimatedPlane - least accurate, can shift

            // 2a. Try existing plane geometry first (most accurate)
            ARRaycastQuery *geometryQuery = [[ARRaycastQuery alloc]
                initWithOrigin:rayOrigin
                direction:rayDirection
                allowingTarget:ARRaycastTargetExistingPlaneGeometry
                alignment:ARRaycastTargetAlignmentAny];

            NSArray<ARRaycastResult *> *geometryResults = [session raycast:geometryQuery];
            if (geometryResults.count > 0) {
                ARRaycastResult *hit = geometryResults.firstObject;
                result.ok = YES;
                result.worldPos = simd_make_float3(
                    hit.worldTransform.columns[3][0],
                    hit.worldTransform.columns[3][1],
                    hit.worldTransform.columns[3][2]
                );
                result.confidence = 0.95f;  // Highest confidence
                result.method = @"raycast_geometry";
                [results addObject:result];
                continue;
            }

            // 2b. Try existing plane infinite (extends beyond detected bounds)
            ARRaycastQuery *infiniteQuery = [[ARRaycastQuery alloc]
                initWithOrigin:rayOrigin
                direction:rayDirection
                allowingTarget:ARRaycastTargetExistingPlaneInfinite
                alignment:ARRaycastTargetAlignmentAny];

            NSArray<ARRaycastResult *> *infiniteResults = [session raycast:infiniteQuery];
            if (infiniteResults.count > 0) {
                ARRaycastResult *hit = infiniteResults.firstObject;
                result.ok = YES;
                result.worldPos = simd_make_float3(
                    hit.worldTransform.columns[3][0],
                    hit.worldTransform.columns[3][1],
                    hit.worldTransform.columns[3][2]
                );
                result.confidence = 0.85f;  // High confidence
                result.method = @"raycast_infinite";
                [results addObject:result];
                continue;
            }

            // 2c. Fall back to estimated planes (least accurate, can drift)
            ARRaycastQuery *estimatedQuery = [[ARRaycastQuery alloc]
                initWithOrigin:rayOrigin
                direction:rayDirection
                allowingTarget:ARRaycastTargetEstimatedPlane
                alignment:ARRaycastTargetAlignmentAny];

            NSArray<ARRaycastResult *> *estimatedResults = [session raycast:estimatedQuery];
            if (estimatedResults.count > 0) {
                ARRaycastResult *hit = estimatedResults.firstObject;
                result.ok = YES;
                result.worldPos = simd_make_float3(
                    hit.worldTransform.columns[3][0],
                    hit.worldTransform.columns[3][1],
                    hit.worldTransform.columns[3][2]
                );
                result.confidence = 0.6f;  // Lower confidence - can shift
                result.method = @"raycast_estimated";
                [results addObject:result];
                continue;
            }
        }

        // 3. Point cloud fallback using STORED feature points from capture time
        //    CRITICAL: Use stored points, NOT current frame!
        if (entry.featurePointsData && entry.featurePointsCount > 0) {
            simd_float3 nearestPoint;
            float nearestDist;
            if ([self findNearestStoredPoint:entry
                                   rayOrigin:rayOrigin
                                rayDirection:rayDirection
                                 maxDistance:0.5f  // 50cm threshold
                                nearestPoint:&nearestPoint
                                 nearestDist:&nearestDist]) {
                result.ok = YES;
                result.worldPos = nearestPoint;
                result.confidence = MAX(0.3f, 0.6f - nearestDist);  // Decreases with distance
                result.method = @"pointcloud";
                [results addObject:result];
                continue;
            }
        }

        // No result
        result.error = @"No depth data available at this point";
        [results addObject:result];
    }

    return results;
}

#pragma mark - LiDAR Depth Sampling (with proper coordinate transform)

+ (BOOL)sampleLiDARDepth:(VROFrameEntry *)entry
                  jpegU:(float)jpegU jpegV:(float)jpegV
               worldPos:(simd_float3 *)outWorldPos
             confidence:(float *)outConfidence {

    CVPixelBufferRef depthBuffer = entry.depthBuffer;
    if (!depthBuffer) return NO;

    CVPixelBufferLockBaseAddress(depthBuffer, kCVPixelBufferLock_ReadOnly);

    size_t depthWidth = CVPixelBufferGetWidth(depthBuffer);
    size_t depthHeight = CVPixelBufferGetHeight(depthBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer);
    Float32 *depthData = (Float32 *)CVPixelBufferGetBaseAddress(depthBuffer);

    // CRITICAL: Transform JPEG UV → AR image UV using jpegToARTransform
    CGAffineTransform t = entry.jpegToARTransform;
    float arU = jpegU * t.a + jpegV * t.c + t.tx;
    float arV = jpegU * t.b + jpegV * t.d + t.ty;

    // V2.3 FIX: Reject out-of-range UV early instead of clamping to edge
    // Clamping would return misleading edge depth values
    if (arU < 0.0f || arU > 1.0f || arV < 0.0f || arV > 1.0f) {
        CVPixelBufferUnlockBaseAddress(depthBuffer, kCVPixelBufferLock_ReadOnly);
        return NO;  // Point is outside AR image bounds
    }

    // Depth buffer is aligned to AR image space
    // Map AR UV to depth buffer pixel coords
    int depthX = (int)(arU * depthWidth);
    int depthY = (int)(arV * depthHeight);

    // Safety clamp for floating point edge cases (should rarely trigger now)
    depthX = MAX(0, MIN((int)depthWidth - 1, depthX));
    depthY = MAX(0, MIN((int)depthHeight - 1, depthY));

    Float32 *row = (Float32 *)((uint8_t *)depthData + depthY * bytesPerRow);
    float depth = row[depthX];

    CVPixelBufferUnlockBaseAddress(depthBuffer, kCVPixelBufferLock_ReadOnly);

    if (depth <= 0 || depth > 10.0f) {
        return NO;  // Invalid depth
    }

    // CRITICAL: Backproject using AR intrinsics and AR pixel coords
    // Depth is aligned to AR image space, so we must use AR-space coordinates
    float fx = entry.intrinsicsAR.columns[0][0];
    float fy = entry.intrinsicsAR.columns[1][1];
    float cx = entry.intrinsicsAR.columns[2][0];
    float cy = entry.intrinsicsAR.columns[2][1];

    // AR pixel coords (not JPEG pixel coords!)
    float arPx = arU * entry.arImageSize.width;
    float arPy = arV * entry.arImageSize.height;

    // Camera-space 3D point using AR intrinsics
    float camX = (arPx - cx) / fx * depth;
    float camY = (arPy - cy) / fy * depth;
    float camZ = -depth;  // ARKit: -Z is forward

    simd_float4 camPoint = simd_make_float4(camX, camY, camZ, 1.0f);
    simd_float4 worldPoint = simd_mul(entry.cameraToWorld, camPoint);

    *outWorldPos = simd_make_float3(worldPoint.x, worldPoint.y, worldPoint.z);
    *outConfidence = 0.95f;

    return YES;
}

#pragma mark - Ray Computation (from JPEG UV)

+ (void)computeRayFromJpegUV:(float)jpegU v:(float)jpegV
                       entry:(VROFrameEntry *)entry
                   rayOrigin:(simd_float3 *)outOrigin
                rayDirection:(simd_float3 *)outDirection {

    // Camera position in world space
    *outOrigin = simd_make_float3(
        entry.cameraToWorld.columns[3][0],
        entry.cameraToWorld.columns[3][1],
        entry.cameraToWorld.columns[3][2]
    );

    // Use JPEG-space intrinsics (with crop offsets)
    float fx = entry.intrinsicsJPEG.columns[0][0];
    float fy = entry.intrinsicsJPEG.columns[1][1];
    float cx = entry.intrinsicsJPEG.columns[2][0];
    float cy = entry.intrinsicsJPEG.columns[2][1];

    float px = jpegU * entry.jpegSize.width;
    float py = jpegV * entry.jpegSize.height;

    // Camera-space ray direction (normalized)
    float camDirX = (px - cx) / fx;
    float camDirY = (py - cy) / fy;
    float camDirZ = -1.0f;  // -Z is forward in ARKit

    simd_float3 camDir = simd_normalize(simd_make_float3(camDirX, camDirY, camDirZ));

    // Transform to world space (rotation only, w=0)
    simd_float4 worldDir4 = simd_mul(entry.cameraToWorld, simd_make_float4(camDir.x, camDir.y, camDir.z, 0));
    *outDirection = simd_normalize(simd_make_float3(worldDir4.x, worldDir4.y, worldDir4.z));
}

#pragma mark - Point Cloud Fallback (using STORED points from capture time)

+ (BOOL)findNearestStoredPoint:(VROFrameEntry *)entry
                     rayOrigin:(simd_float3)rayOrigin
                  rayDirection:(simd_float3)rayDirection
                   maxDistance:(float)maxDistance
                  nearestPoint:(simd_float3 *)outPoint
                   nearestDist:(float *)outDist {

    if (!entry.featurePointsData || entry.featurePointsCount == 0) {
        return NO;
    }

    const simd_float3 *points = (const simd_float3 *)entry.featurePointsData.bytes;
    NSUInteger count = entry.featurePointsCount;

    float bestDist = maxDistance;
    BOOL found = NO;

    for (NSUInteger i = 0; i < count; i++) {
        simd_float3 point = points[i];

        // Distance from point to ray
        simd_float3 toPoint = point - rayOrigin;
        float t = simd_dot(toPoint, rayDirection);

        if (t < 0.1f) continue;  // Behind camera or too close

        simd_float3 closestOnRay = rayOrigin + t * rayDirection;
        float dist = simd_length(point - closestOnRay);

        if (dist < bestDist) {
            bestDist = dist;
            *outPoint = point;
            found = YES;
        }
    }

    if (found) {
        *outDist = bestDist;
    }

    return found;
}

@end
