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


/// A depth map with the JPEG-UV rectangle it covers. The full-frame map
/// covers (0,0)-(1,1); a crop map covers the square it was cut from.
@interface VROMonoDepthMap : NSObject
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;
@property (nonatomic, assign) CGRect coverage;  // in upright-JPEG UV
@end
@implementation VROMonoDepthMap
@end

/// Helpers defined below their first use.
@interface VRODetectionResolver ()
+ (void)computeRayFromJpegUV:(float)jpegU v:(float)jpegV
                       entry:(VROFrameEntry *)entry
                   rayOrigin:(simd_float3 *)outOrigin
                rayDirection:(simd_float3 *)outDirection;
+ (BOOL)findNearestStoredPoint:(VROFrameEntry *)entry
                     rayOrigin:(simd_float3)rayOrigin
                  rayDirection:(simd_float3)rayDirection
                   maxDistance:(float)maxDistance
                  nearestPoint:(simd_float3 *)outPoint
                   nearestDist:(float *)outDist;
+ (float)monoDepthForEntry:(VROFrameEntry *)entry
                  provider:(VROMonoDepthProvider)provider
                    inputU:(float)inputU inputV:(float)inputV
                       box:(nullable NSArray *)box
               cropEnabled:(BOOL)cropEnabled;
+ (BOOL)backprojectJpegU:(float)jpegU v:(float)jpegV
                   depth:(float)depth
                   entry:(VROFrameEntry *)entry
                worldPos:(simd_float3 *)outWorldPos;
@end

#pragma mark - VRODetectionResolver Implementation

@implementation VRODetectionResolver

+ (NSArray<VRODetectionResult *> *)resolvePoints:(NSArray<NSDictionary *> *)points
                                      frameEntry:(VROFrameEntry *)entry
                                       arSession:(ARSession *)session {
    return [self resolvePoints:points frameEntry:entry arSession:session monoDepthProvider:nil];
}

+ (NSArray<VRODetectionResult *> *)resolvePoints:(NSArray<NSDictionary *> *)points
                                      frameEntry:(VROFrameEntry *)entry
                                       arSession:(ARSession *)session
                               monoDepthProvider:(nullable VROMonoDepthProvider)monoDepth {
    return [self resolvePoints:points frameEntry:entry arSession:session monoDepthProvider:monoDepth options:nil];
}

/// Camera-space depth (metres along the optical axis) of a world point at
/// this entry's capture pose. The unit every depth source here speaks.
static inline float VROCameraDepthOf(VROFrameEntry *entry, simd_float3 world) {
    simd_float4x4 worldToCam = simd_inverse(entry.cameraToWorld);
    simd_float4 c = simd_mul(worldToCam, simd_make_float4(world.x, world.y, world.z, 1.0f));
    return -c.z;  // ARKit camera looks down -Z
}

/// The app's `expectedSpreadM('mono', range)` (ADR-0035 error table), mirrored
/// here so the gate and the ledger disagree about nothing. Provisional until a
/// field walk replaces it — change both together.
static inline float VROMonoExpectedSpreadM(float rangeM) {
    return 0.06f + 0.09f * MAX(0.0f, rangeM);
}
/// How far a raycast may sit from the mono estimate before the rung is
/// refused. 2x the model's own expected spread: the gate catches a plane
/// extended a room too far, not the model's ordinary error.
static const float kMonoGateToleranceFactor = 2.0f;

+ (NSArray<VRODetectionResult *> *)resolvePoints:(NSArray<NSDictionary *> *)points
                                      frameEntry:(VROFrameEntry *)entry
                                       arSession:(ARSession *)session
                               monoDepthProvider:(nullable VROMonoDepthProvider)monoDepth
                                         options:(nullable NSDictionary *)options {

    NSMutableArray<VRODetectionResult *> *results = [NSMutableArray arrayWithCapacity:points.count];
    const BOOL cropEnabled = [options[@"monoDepthCrop"] boolValue];

    for (NSDictionary *point in points) {
        float inputU = [point[@"x"] floatValue];  // Normalized 0-1 (portrait space if rotated)
        float inputV = [point[@"y"] floatValue];
        // Optional detection box in the same space: [xmin, ymin, xmax, ymax].
        // Lets the mono path run on a crop around the thing (REP-954).
        NSArray *box = [point[@"box"] isKindOfClass:[NSArray class]] && [point[@"box"] count] == 4
            ? point[@"box"] : nil;

        VRODetectionResult *result = [[VRODetectionResult alloc] init];
        result.inputX = inputU;
        result.inputY = inputV;
        result.ok = NO;
        result.gated = 0;

        // If frame was rotated for portrait display, map coordinates back to landscape
        // Portrait UV → Landscape UV: u' = v, v' = 1 - u
        // This reverses the 90° CCW rotation applied to the image
        float jpegU, jpegV;
        if (entry.rotatedToPortrait) {
            jpegU = inputV;           // Portrait Y → Landscape X
            jpegV = 1.0f - inputU;    // Portrait X → inverted Landscape Y
        } else {
            jpegU = inputU;
            jpegV = inputV;
        }

        // The ray through this pixel at capture pose. Computed up front and
        // attached to EVERY result (REP-952): a point no rung can answer
        // still leaves the ledger a ray to triangulate against a later one,
        // and a resolved position lets JS check that it lies on the ray.
        simd_float3 rayOrigin, rayDirection;
        [self computeRayFromJpegUV:jpegU v:jpegV
                             entry:entry
                         rayOrigin:&rayOrigin
                      rayDirection:&rayDirection];
        result.hasRay = YES;
        result.rayOrigin = rayOrigin;
        result.rayDirection = rayDirection;

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
        if (@available(iOS 14.0, *)) {
            // 2a. Existing plane geometry: a MEASURED surface, never gated.
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

            // Monocular depth for this pixel, estimated ON DEMAND from the
            // frame's own JPEG (fork >= 2.61.72). Two roles below: the
            // consistency gate on every guessed rung (REP-951), and the
            // answer when no guess survives. 0 when unavailable.
            float monoZ = 0.0f;
            if (monoDepth) {
                monoZ = [self monoDepthForEntry:entry
                                       provider:monoDepth
                                         inputU:inputU inputV:inputV
                                            box:box
                                    cropEnabled:cropEnabled];
            }
            const float monoTol = monoZ > 0.0f
                ? kMonoGateToleranceFactor * VROMonoExpectedSpreadM(monoZ) : 0.0f;
            // A guessed rung's hit is accepted only when mono, if present,
            // agrees with it. Where they agree the raycast wins: it is the
            // more precise of the two on a real surface.
            BOOL (^acceptGuess)(simd_float3) = ^BOOL(simd_float3 hit) {
                if (monoZ <= 0.0f) return YES;
                float hitZ = VROCameraDepthOf(entry, hit);
                return fabsf(hitZ - monoZ) <= monoTol;
            };

            // 2b. Existing plane extended to infinity (beyond detected bounds)
            ARRaycastQuery *infiniteQuery = [[ARRaycastQuery alloc]
                initWithOrigin:rayOrigin
                direction:rayDirection
                allowingTarget:ARRaycastTargetExistingPlaneInfinite
                alignment:ARRaycastTargetAlignmentAny];

            NSArray<ARRaycastResult *> *infiniteResults = [session raycast:infiniteQuery];
            if (infiniteResults.count > 0) {
                ARRaycastResult *hit = infiniteResults.firstObject;
                simd_float3 pos = simd_make_float3(
                    hit.worldTransform.columns[3][0],
                    hit.worldTransform.columns[3][1],
                    hit.worldTransform.columns[3][2]
                );
                if (acceptGuess(pos)) {
                    result.ok = YES;
                    result.worldPos = pos;
                    result.confidence = 0.85f;  // High confidence
                    result.method = @"raycast_infinite";
                    [results addObject:result];
                    continue;
                }
                result.gated += 1;
            }

            // 2c. Estimated planes (least accurate, can drift)
            ARRaycastQuery *estimatedQuery = [[ARRaycastQuery alloc]
                initWithOrigin:rayOrigin
                direction:rayDirection
                allowingTarget:ARRaycastTargetEstimatedPlane
                alignment:ARRaycastTargetAlignmentAny];

            NSArray<ARRaycastResult *> *estimatedResults = [session raycast:estimatedQuery];
            if (estimatedResults.count > 0) {
                ARRaycastResult *hit = estimatedResults.firstObject;
                simd_float3 pos = simd_make_float3(
                    hit.worldTransform.columns[3][0],
                    hit.worldTransform.columns[3][1],
                    hit.worldTransform.columns[3][2]
                );
                if (acceptGuess(pos)) {
                    result.ok = YES;
                    result.worldPos = pos;
                    result.confidence = 0.6f;  // Lower confidence - can shift
                    result.method = @"raycast_estimated";
                    [results addObject:result];
                    continue;
                }
                result.gated += 1;
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
                    if (acceptGuess(nearestPoint)) {
                        result.ok = YES;
                        result.worldPos = nearestPoint;
                        result.confidence = MAX(0.3f, 0.6f - nearestDist);  // Decreases with distance
                        result.method = @"pointcloud";
                        [results addObject:result];
                        continue;
                    }
                    result.gated += 1;
                }
            }

            // 4. Monocular depth: the off-plane case, or every guess refused.
            if (monoZ > 0.0f) {
                simd_float3 monoPos;
                if ([self backprojectJpegU:jpegU v:jpegV depth:monoZ entry:entry worldPos:&monoPos]) {
                    result.ok = YES;
                    result.worldPos = monoPos;
                    result.confidence = 0.7f;  // below measured geometry, above a guessed plane
                    result.method = @"mono";
                    [results addObject:result];
                    continue;
                }
            }
        }

        // No result — the ray still rides the result for triangulation.
        result.error = result.gated > 0
            ? @"Every raycast disagreed with the depth estimate at this point"
            : @"No depth data available at this point";
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

    // Camera-space 3D point using AR intrinsics.
    // Image v grows DOWN while ARKit camera-space +y points UP, so the y
    // term must be negated — without it every resolved point is mirrored
    // about the camera's horizontal axis (left-right mirrored in portrait).
    float camX = (arPx - cx) / fx * depth;
    float camY = -(arPy - cy) / fy * depth;
    float camZ = -depth;  // ARKit: -Z is forward

    simd_float4 camPoint = simd_make_float4(camX, camY, camZ, 1.0f);
    simd_float4 worldPoint = simd_mul(entry.cameraToWorld, camPoint);

    *outWorldPos = simd_make_float3(worldPoint.x, worldPoint.y, worldPoint.z);
    *outConfidence = 0.95f;

    return YES;
}

#pragma mark - Monocular Depth (on demand, cached per frame entry)

/// Crops per frame before the mono path falls back to the full-frame map:
/// each crop is one inference, and a frame with many detections must not
/// turn into many inferences.
static const NSUInteger kMaxMonoCropsPerEntry = 3;
/// Crop side = box's longer side × this, so the model sees the thing with
/// its surroundings rather than a tight patch with no depth cues.
static const float kMonoCropContextFactor = 2.0f;
static const float kMonoCropMinSideUV = 0.25f;

+ (VROMonoDepthMap *)runMonoDepthOn:(CIImage *)image
                          coverage:(CGRect)coverage
                          provider:(VROMonoDepthProvider)provider {
    int width = 0, height = 0;
    NSData *depth = provider(image, &width, &height);
    if (!depth || width <= 0 || height <= 0 ||
        depth.length < (NSUInteger)width * (NSUInteger)height * sizeof(float)) {
        return nil;
    }
    VROMonoDepthMap *map = [[VROMonoDepthMap alloc] init];
    map.data = depth;
    map.width = width;
    map.height = height;
    map.coverage = coverage;
    return map;
}

/// The frame's upright JPEG as a CIImage, or nil. The bytes were encoded
/// upright (rotated before encoding); the orientation tag is applied anyway
/// so the depth map is in the space JS reports in.
+ (CIImage *)uprightImageForEntry:(VROFrameEntry *)entry {
    // The hi-res variant of the SAME frame shares the small stream's crop,
    // so either image maps to the same UV; prefer the detail when present.
    NSData *imageData = entry.hiResJpegData ?: entry.jpegData;
    if (!imageData) return nil;
    return [CIImage imageWithData:imageData
                          options:@{kCIImageApplyOrientationProperty: @YES}];
}

+ (BOOL)monoThermalAllows {
    // The per-frame loop stops at Critical; on demand follows the same
    // rule rather than adding heat when the device asks for none.
    return [NSProcessInfo processInfo].thermalState != NSProcessInfoThermalStateCritical;
}

+ (VROMonoDepthMap *)fullFrameMonoMapForEntry:(VROFrameEntry *)entry
                                      provider:(VROMonoDepthProvider)provider {
    @synchronized (entry) {
        if (entry.monoDepthAttempted) {
            if (!entry.monoDepthData) return nil;
            VROMonoDepthMap *map = [[VROMonoDepthMap alloc] init];
            map.data = entry.monoDepthData;
            map.width = entry.monoDepthWidth;
            map.height = entry.monoDepthHeight;
            map.coverage = CGRectMake(0, 0, 1, 1);
            return map;
        }
        entry.monoDepthAttempted = YES;
        if (![self monoThermalAllows]) return nil;
        CIImage *image = [self uprightImageForEntry:entry];
        if (!image) return nil;
        VROMonoDepthMap *map = [self runMonoDepthOn:image coverage:CGRectMake(0, 0, 1, 1) provider:provider];
        if (!map) return nil;
        entry.monoDepthData = map.data;
        entry.monoDepthWidth = map.width;
        entry.monoDepthHeight = map.height;
        return map;
    }
}

/// A square crop around the detection box, cached per (frame, box). Nil
/// when the crop budget for this frame is spent or the crop failed — the
/// caller then falls back to the full-frame map.
+ (VROMonoDepthMap *)cropMonoMapForEntry:(VROFrameEntry *)entry
                                     box:(NSArray *)box
                                provider:(VROMonoDepthProvider)provider {
    float xmin = [box[0] floatValue], ymin = [box[1] floatValue];
    float xmax = [box[2] floatValue], ymax = [box[3] floatValue];
    if (!(xmax > xmin && ymax > ymin)) return nil;
    NSString *key = [NSString stringWithFormat:@"%.3f,%.3f,%.3f,%.3f", xmin, ymin, xmax, ymax];

    @synchronized (entry) {
        if (!entry.monoCropMaps) entry.monoCropMaps = [NSMutableDictionary dictionary];
        id cached = entry.monoCropMaps[key];
        if (cached) return cached == [NSNull null] ? nil : (VROMonoDepthMap *)cached;
        if (entry.monoCropMaps.count >= kMaxMonoCropsPerEntry) return nil;
        entry.monoCropMaps[key] = [NSNull null];  // attempted; overwritten on success
        if (![self monoThermalAllows]) return nil;

        CIImage *image = [self uprightImageForEntry:entry];
        if (!image) return nil;
        CGRect extent = image.extent;
        if (extent.size.width <= 0 || extent.size.height <= 0) return nil;

        // Square side in UV of the upright image's shorter dimension, so the
        // crop is square in PIXELS (what the model wants) and clamped inside.
        float imgW = extent.size.width, imgH = extent.size.height;
        float boxWpx = (xmax - xmin) * imgW, boxHpx = (ymax - ymin) * imgH;
        float sidePx = MAX(boxWpx, boxHpx) * kMonoCropContextFactor;
        sidePx = MAX(sidePx, kMonoCropMinSideUV * MIN(imgW, imgH));
        sidePx = MIN(sidePx, MIN(imgW, imgH));
        float cxPx = (xmin + xmax) * 0.5f * imgW, cyPx = (ymin + ymax) * 0.5f * imgH;
        float x0 = MAX(0.0f, MIN(imgW - sidePx, cxPx - sidePx * 0.5f));
        float y0 = MAX(0.0f, MIN(imgH - sidePx, cyPx - sidePx * 0.5f));
        // CIImage origin is bottom-left; JPEG UV v grows downward.
        CGRect cropRectCI = CGRectMake(extent.origin.x + x0,
                                       extent.origin.y + (imgH - y0 - sidePx),
                                       sidePx, sidePx);
        CIImage *cropped = [[image imageByCroppingToRect:cropRectCI]
            imageByApplyingTransform:CGAffineTransformMakeTranslation(-cropRectCI.origin.x, -cropRectCI.origin.y)];
        CGRect coverage = CGRectMake(x0 / imgW, y0 / imgH, sidePx / imgW, sidePx / imgH);
        VROMonoDepthMap *map = [self runMonoDepthOn:cropped coverage:coverage provider:provider];
        if (!map) return nil;
        entry.monoCropMaps[key] = map;
        return map;
    }
}

/// 3x3 median of the map at UV (in the map's own coverage space). 0 when
/// fewer than five neighbours carry a valid depth.
+ (float)sampleMonoMap:(VROMonoDepthMap *)map u:(float)u v:(float)v {
    const int width = map.width, height = map.height;
    const float *depthMap = (const float *)map.data.bytes;
    int cx = (int)lroundf(u * (width - 1));
    int cy = (int)lroundf(v * (height - 1));
    float samples[9];
    int count = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int x = cx + dx, y = cy + dy;
            if (x < 0 || y < 0 || x >= width || y >= height) continue;
            float d = depthMap[y * width + x];
            if (d > 0.0f && isfinite(d)) samples[count++] = d;
        }
    }
    if (count < 5) return 0.0f;
    for (int i = 1; i < count; i++) {
        float value = samples[i];
        int j = i - 1;
        while (j >= 0 && samples[j] > value) { samples[j + 1] = samples[j]; j--; }
        samples[j + 1] = value;
    }
    return samples[count / 2];
}

/// Metric depth (camera-space z, metres) at an upright-JPEG UV, from the
/// crop map when a box is given and crops are enabled, else the full-frame
/// map. 0 when unavailable or implausible. A learned depth beyond 8 m is a
/// guess, so it is refused rather than reported.
+ (float)monoDepthForEntry:(VROFrameEntry *)entry
                  provider:(VROMonoDepthProvider)provider
                    inputU:(float)inputU inputV:(float)inputV
                       box:(nullable NSArray *)box
               cropEnabled:(BOOL)cropEnabled {
    if (inputU < 0.0f || inputU > 1.0f || inputV < 0.0f || inputV > 1.0f) return 0.0f;

    VROMonoDepthMap *map = nil;
    if (cropEnabled && box) {
        map = [self cropMonoMapForEntry:entry box:box provider:provider];
    }
    if (!map) {
        map = [self fullFrameMonoMapForEntry:entry provider:provider];
    }
    if (!map) return 0.0f;

    CGRect cov = map.coverage;
    if (cov.size.width <= 0 || cov.size.height <= 0) return 0.0f;
    float u = (inputU - cov.origin.x) / cov.size.width;
    float v = (inputV - cov.origin.y) / cov.size.height;
    if (u < 0.0f || u > 1.0f || v < 0.0f || v > 1.0f) return 0.0f;

    float depth = [self sampleMonoMap:map u:u v:v];
    if (depth < 0.1f || depth > 8.0f) return 0.0f;
    return depth;
}

/// Pinhole backprojection at a camera-space depth, with the JPEG-space
/// intrinsics (landscape, crop offsets applied) at the landscape JPEG UV —
/// the same frame the ray path uses, so every depth source shares one
/// geometry. Same y negation as the LiDAR path: image v is down, camera +y is up.
+ (BOOL)backprojectJpegU:(float)jpegU v:(float)jpegV
                   depth:(float)depth
                   entry:(VROFrameEntry *)entry
                worldPos:(simd_float3 *)outWorldPos {
    float fx = entry.intrinsicsJPEG.columns[0][0];
    float fy = entry.intrinsicsJPEG.columns[1][1];
    float cxJ = entry.intrinsicsJPEG.columns[2][0];
    float cyJ = entry.intrinsicsJPEG.columns[2][1];
    if (fx <= 0.0f || fy <= 0.0f || depth <= 0.0f) return NO;

    float landscapeWidth, landscapeHeight;
    if (entry.rotatedToPortrait) {
        landscapeWidth = entry.jpegSize.height;
        landscapeHeight = entry.jpegSize.width;
    } else {
        landscapeWidth = entry.jpegSize.width;
        landscapeHeight = entry.jpegSize.height;
    }
    float px = jpegU * landscapeWidth;
    float py = jpegV * landscapeHeight;

    float camX = (px - cxJ) / fx * depth;
    float camY = -(py - cyJ) / fy * depth;
    float camZ = -depth;

    simd_float4 camPoint = simd_make_float4(camX, camY, camZ, 1.0f);
    simd_float4 worldPoint = simd_mul(entry.cameraToWorld, camPoint);
    *outWorldPos = simd_make_float3(worldPoint.x, worldPoint.y, worldPoint.z);
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
    // Note: intrinsicsJPEG is always in LANDSCAPE space (pre-rotation)
    float fx = entry.intrinsicsJPEG.columns[0][0];
    float fy = entry.intrinsicsJPEG.columns[1][1];
    float cx = entry.intrinsicsJPEG.columns[2][0];
    float cy = entry.intrinsicsJPEG.columns[2][1];

    // Get landscape JPEG dimensions for pixel calculation
    // jpegU/jpegV are already in landscape space (transformed from portrait if needed)
    // jpegSize stores portrait dimensions, so we swap if rotated
    float landscapeWidth, landscapeHeight;
    if (entry.rotatedToPortrait) {
        landscapeWidth = entry.jpegSize.height;   // Portrait height = landscape width
        landscapeHeight = entry.jpegSize.width;   // Portrait width = landscape height
    } else {
        landscapeWidth = entry.jpegSize.width;
        landscapeHeight = entry.jpegSize.height;
    }

    float px = jpegU * landscapeWidth;
    float py = jpegV * landscapeHeight;

    // Camera-space ray direction (normalized).
    // Same y negation as sampleLiDARDepth: image v is down, camera +y is up.
    float camDirX = (px - cx) / fx;
    float camDirY = -(py - cy) / fy;
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
