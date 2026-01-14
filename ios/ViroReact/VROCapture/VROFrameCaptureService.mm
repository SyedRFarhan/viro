//
//  VROFrameCaptureService.mm
//  ViroReact
//
//  Main service implementation for AR frame capture and JPEG encoding.
//
//  Copyright © 2024 Viro Media. All rights reserved.
//

#import "VROFrameCaptureService.h"
#import "VROFrameRingBuffer.h"
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
#import <atomic>

#pragma mark - Helper Class for JPEG Encode Result

@interface VROJpegEncodeResult : NSObject
@property (nonatomic, strong) NSData *jpegData;
@property (nonatomic, assign) float scale;
@property (nonatomic, assign) float cropX;
@property (nonatomic, assign) float cropY;
@end

@implementation VROJpegEncodeResult
@end


#pragma mark - VROFrameCaptureService Implementation

@implementation VROFrameCaptureService {
    dispatch_queue_t _processingQueue;
    std::atomic<bool> _isProcessing;
    double _lastCaptureTime;
    CIContext *_ciContext;
    VROFrameRingBuffer *_ringBuffer;
    NSUInteger _frameCounter;
}

- (instancetype)initWithRingBufferCapacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        // Create serial processing queue with user-initiated QoS
        _processingQueue = dispatch_queue_create(
            "com.viro.frameCaptureService",
            DISPATCH_QUEUE_SERIAL
        );
        dispatch_set_target_queue(
            _processingQueue,
            dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
        );

        _ringBuffer = [[VROFrameRingBuffer alloc] initWithCapacity:capacity];

        // GPU-accelerated CIContext for fast JPEG encoding
        _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];

        _isProcessing = false;
        _lastCaptureTime = 0;

        // Defaults
        _jpegQuality = 0.7;
        _targetFPS = 5;
        _targetWidth = 640;
        _targetHeight = 480;
        _frameCounter = 0;
    }
    return self;
}

- (void)onARFrame:(ARFrame *)frame session:(ARSession *)session {
    if (!_enabled || !frame) {
        return;
    }

    double timestamp = frame.timestamp;

    // Rate limit check
    double minInterval = 1.0 / _targetFPS;
    double elapsed = timestamp - _lastCaptureTime;
    if (elapsed < minInterval) {
        // Only log occasionally to avoid spam
        static int skipCount = 0;
        skipCount++;
        if (skipCount % 60 == 0) {
            NSLog(@"[ViroFrameStream DEBUG] Rate limit: skipped %d frames (interval=%.3fs, need=%.3fs)",
                  skipCount, elapsed, minInterval);
        }
        return;
    }

    // Busy check (non-blocking) using atomic compare-exchange
    bool expected = false;
    if (!_isProcessing.compare_exchange_strong(expected, true)) {
        NSLog(@"[ViroFrameStream DEBUG] Busy: still processing previous frame, dropping");
        return;
    }

    _lastCaptureTime = timestamp;
    NSLog(@"[ViroFrameStream DEBUG] Capturing frame #%lu at timestamp %.3f", (unsigned long)_frameCounter, timestamp);

    // Generate unique frameId
    NSString *frameId = [NSString stringWithFormat:@"%lu_%f",
                         (unsigned long)_frameCounter++, timestamp];

    // Capture data from ARFrame (must be done on calling thread before async)
    CVPixelBufferRef pixelBuffer = frame.capturedImage;
    if (!pixelBuffer) {
        NSLog(@"[ViroFrameStream DEBUG] No pixel buffer available for frame %@", frameId);
        _isProcessing = false;
        return;
    }
    CVPixelBufferRetain(pixelBuffer);

    matrix_float3x3 arIntrinsics = frame.camera.intrinsics;
    simd_float4x4 cameraTransform = frame.camera.transform;
    ARTrackingState trackingState = frame.camera.trackingState;

    // V2.3 FIX: Use CVPixelBuffer dimensions as SINGLE SOURCE OF TRUTH
    // This ensures arImageSize matches exactly what we encode
    size_t srcWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t srcHeight = CVPixelBufferGetHeight(pixelBuffer);
    CGSize arImageSize = CGSizeMake(srcWidth, srcHeight);

    // Capture LiDAR depth if available (iOS 14.0+ on Pro devices)
    CVPixelBufferRef depthBuffer = nil;
    CGSize depthBufferSize = CGSizeZero;
    if (@available(iOS 14.0, *)) {
        if (frame.sceneDepth.depthMap) {
            depthBuffer = frame.sceneDepth.depthMap;
            CVPixelBufferRetain(depthBuffer);
            depthBufferSize = CGSizeMake(
                CVPixelBufferGetWidth(depthBuffer),
                CVPixelBufferGetHeight(depthBuffer)
            );
        }
    }

    // Capture feature points at frame time (for fallback resolution)
    // CAP at 2000 points max to avoid memory issues
    static const NSUInteger kMaxFeaturePoints = 2000;
    NSData *featurePointsData = nil;
    NSUInteger featurePointsCount = 0;

    if (frame.rawFeaturePoints && frame.rawFeaturePoints.count > 0) {
        NSUInteger originalCount = frame.rawFeaturePoints.count;
        featurePointsCount = MIN(originalCount, kMaxFeaturePoints);

        // Downsample if needed (stride sampling)
        NSUInteger stride = (originalCount > kMaxFeaturePoints)
            ? (originalCount / kMaxFeaturePoints) : 1;

        size_t dataSize = featurePointsCount * sizeof(simd_float3);
        NSMutableData *pointsData = [NSMutableData dataWithLength:dataSize];
        simd_float3 *dst = (simd_float3 *)pointsData.mutableBytes;
        NSUInteger dstIdx = 0;

        for (NSUInteger i = 0; i < originalCount && dstIdx < kMaxFeaturePoints; i += stride) {
            dst[dstIdx++] = simd_make_float3(
                frame.rawFeaturePoints.points[i][0],
                frame.rawFeaturePoints.points[i][1],
                frame.rawFeaturePoints.points[i][2]
            );
        }
        featurePointsCount = dstIdx;
        featurePointsData = pointsData;
    }

    // Capture config values for async block
    int targetWidth = _targetWidth;
    int targetHeight = _targetHeight;
    float jpegQuality = _jpegQuality;
    NSInteger sessionId = [_ringBuffer currentSessionId];

    // Process on background queue
    dispatch_async(_processingQueue, ^{
        @autoreleasepool {
            // 1. Encode JPEG with scale+crop (EXACT target dimensions)
            VROJpegEncodeResult *encodeResult = [self encodeJPEGWithCrop:pixelBuffer
                                                            targetWidth:targetWidth
                                                           targetHeight:targetHeight
                                                                quality:jpegQuality];
            CVPixelBufferRelease(pixelBuffer);

            if (!encodeResult || !encodeResult.jpegData) {
                NSLog(@"[ViroFrameStream DEBUG] JPEG encode FAILED for frame %@", frameId);
                if (depthBuffer) CVPixelBufferRelease(depthBuffer);
                self->_isProcessing = false;
                return;
            }

            NSLog(@"[ViroFrameStream DEBUG] JPEG encoded: %lu bytes, scale=%.3f, crop=(%.1f, %.1f)",
                  (unsigned long)encodeResult.jpegData.length, encodeResult.scale,
                  encodeResult.cropX, encodeResult.cropY);

            float scale = encodeResult.scale;
            float cropX = encodeResult.cropX;
            float cropY = encodeResult.cropY;

            // 2. Calculate JPEG-space intrinsics WITH CROP OFFSETS
            // fx' = fx * scale
            // fy' = fy * scale
            // cx' = (cx * scale) - cropX   <-- CRITICAL: subtract crop offset!
            // cy' = (cy * scale) - cropY
            matrix_float3x3 intrinsicsJPEG = arIntrinsics;
            intrinsicsJPEG.columns[0][0] *= scale;  // fx
            intrinsicsJPEG.columns[1][1] *= scale;  // fy
            intrinsicsJPEG.columns[2][0] = arIntrinsics.columns[2][0] * scale - cropX;  // cx
            intrinsicsJPEG.columns[2][1] = arIntrinsics.columns[2][1] * scale - cropY;  // cy

            // 3. Calculate jpegToARTransform: JPEG UV (0-1) → AR image UV (0-1)
            //
            // Pipeline (forward):
            //   scaled_px = AR_px * scale
            //   JPEG_px = scaled_px - crop  (center crop)
            //
            // Inverse (what we need):
            //   scaled_px = JPEG_px + crop
            //   AR_px = scaled_px / scale = (JPEG_px + crop) / scale
            //
            // In UV space:
            //   JPEG_px = jpegU * targetWidth
            //   AR_px = (JPEG_px + cropX) / scale
            //   AR_u = AR_px / arWidth = (jpegU * targetWidth + cropX) / (scale * arWidth)
            //        = jpegU * (targetWidth / (scale * arWidth)) + cropX / (scale * arWidth)
            //
            // So the transform coefficients are:
            //   a = targetWidth / (scale * arWidth)     <-- CRITICAL: divide by scale!
            //   d = targetHeight / (scale * arHeight)
            //   tx = cropX / (scale * arWidth)
            //   ty = cropY / (scale * arHeight)
            float scaledARWidth = scale * arImageSize.width;
            float scaledARHeight = scale * arImageSize.height;

            float jpegToAR_scaleX = (float)targetWidth / scaledARWidth;
            float jpegToAR_scaleY = (float)targetHeight / scaledARHeight;
            float jpegToAR_offsetX = cropX / scaledARWidth;
            float jpegToAR_offsetY = cropY / scaledARHeight;

            // CGAffineTransform: result = input * [a b; c d] + [tx ty]
            CGAffineTransform jpegToARTransform = CGAffineTransformMake(
                jpegToAR_scaleX, 0,                    // a, b
                0, jpegToAR_scaleY,                    // c, d
                jpegToAR_offsetX, jpegToAR_offsetY    // tx, ty
            );

            // 4. Create ring buffer entry
            VROFrameEntry *entry = [[VROFrameEntry alloc] init];
            entry.frameId = frameId;
            entry.timestamp = timestamp;
            entry.sessionId = sessionId;
            entry.cameraToWorld = cameraTransform;

            entry.intrinsicsJPEG = intrinsicsJPEG;
            entry.jpegSize = CGSizeMake(targetWidth, targetHeight);

            entry.intrinsicsAR = arIntrinsics;
            entry.arImageSize = arImageSize;

            entry.jpegToARTransform = jpegToARTransform;
            entry.cropX = cropX;
            entry.cropY = cropY;
            entry.scale = scale;

            entry.jpegData = encodeResult.jpegData;
            entry.depthBuffer = depthBuffer;  // Transfer ownership
            entry.depthBufferSize = depthBufferSize;

            entry.featurePointsData = featurePointsData;
            entry.featurePointsCount = featurePointsCount;

            [self->_ringBuffer addEntry:entry];
            NSLog(@"[ViroFrameStream DEBUG] Stored frame %@ in ring buffer (sessionId=%ld)", frameId, (long)sessionId);

            // 5. Build event payload (no depth data - too large)
            NSMutableDictionary *event = [NSMutableDictionary dictionary];
            event[@"frameId"] = frameId;
            event[@"timestamp"] = @(timestamp);
            event[@"sessionId"] = @(sessionId);
            event[@"imageData"] = [encodeResult.jpegData base64EncodedStringWithOptions:0];
            event[@"width"] = @(targetWidth);
            event[@"height"] = @(targetHeight);

            event[@"intrinsics"] = @{
                @"fx": @(intrinsicsJPEG.columns[0][0]),
                @"fy": @(intrinsicsJPEG.columns[1][1]),
                @"cx": @(intrinsicsJPEG.columns[2][0]),
                @"cy": @(intrinsicsJPEG.columns[2][1])
            };

            // Flatten 4x4 matrix (column-major)
            NSMutableArray *matrixArray = [NSMutableArray arrayWithCapacity:16];
            for (int col = 0; col < 4; col++) {
                for (int row = 0; row < 4; row++) {
                    [matrixArray addObject:@(cameraTransform.columns[col][row])];
                }
            }
            event[@"cameraToWorld"] = matrixArray;

            // jpegToARTransform as 3x3 matrix (affine transform)
            event[@"jpegToARTransform"] = @[
                @(jpegToARTransform.a), @(jpegToARTransform.b), @(0),
                @(jpegToARTransform.c), @(jpegToARTransform.d), @(0),
                @(jpegToARTransform.tx), @(jpegToARTransform.ty), @(1)
            ];

            NSString *trackingStr = @"normal";
            if (trackingState == ARTrackingStateLimited) {
                trackingStr = @"limited";
            } else if (trackingState == ARTrackingStateNotAvailable) {
                trackingStr = @"notAvailable";
            }
            event[@"trackingState"] = trackingStr;

            // 6. V2.3 FIX: Clear _isProcessing BEFORE dispatching to main thread
            // This ensures capture isn't blocked by JS event delivery latency
            self->_isProcessing = false;

            // Emit to JS (non-blocking - event queued to main thread)
            if (self.onFrameReady) {
                NSLog(@"[ViroFrameStream DEBUG] Emitting frame %@ to JS (%dx%d, tracking=%@)",
                      frameId, targetWidth, targetHeight, event[@"trackingState"]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onFrameReady(event);
                });
            } else {
                NSLog(@"[ViroFrameStream DEBUG] Frame %@ ready but no onFrameReady callback set!", frameId);
            }
        }
    });
}

#pragma mark - JPEG Encoding with Scale+Crop

/**
 * Encode JPEG with SCALE+CROP (cover) for EXACT target dimensions.
 * Uses MAX scale factor to ensure the scaled image covers the target area,
 * then center-crops to exact dimensions.
 */
- (VROJpegEncodeResult *)encodeJPEGWithCrop:(CVPixelBufferRef)pixelBuffer
                                targetWidth:(int)targetWidth
                               targetHeight:(int)targetHeight
                                    quality:(float)quality {

    // Safety check for nil pixelBuffer
    if (!pixelBuffer) {
        NSLog(@"[ViroFrameStream DEBUG] encodeJPEGWithCrop: pixelBuffer is NULL");
        return nil;
    }

    // Safety check for CIContext
    if (!_ciContext) {
        NSLog(@"[ViroFrameStream DEBUG] encodeJPEGWithCrop: _ciContext is NULL");
        return nil;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    if (!ciImage) {
        NSLog(@"[ViroFrameStream DEBUG] encodeJPEGWithCrop: Failed to create CIImage");
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return nil;
    }

    size_t srcWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t srcHeight = CVPixelBufferGetHeight(pixelBuffer);

    // Use MAX scale (cover) to ensure we can crop to exact target size
    float scaleX = (float)targetWidth / srcWidth;
    float scaleY = (float)targetHeight / srcHeight;
    float scale = MAX(scaleX, scaleY);  // COVER, not fit!

    // Scale the image
    CIImage *scaledImage = [ciImage imageByApplyingTransform:
                           CGAffineTransformMakeScale(scale, scale)];

    // Calculate crop rect (center crop)
    CGRect scaledExtent = scaledImage.extent;
    float scaledWidth = scaledExtent.size.width;
    float scaledHeight = scaledExtent.size.height;

    // Crop offsets in SCALED space (same as JPEG pixels)
    float cropX = (scaledWidth - targetWidth) / 2.0f;
    float cropY = (scaledHeight - targetHeight) / 2.0f;

    // Crop rect in scaled image coordinates
    CGRect cropRect = CGRectMake(
        scaledExtent.origin.x + cropX,
        scaledExtent.origin.y + cropY,
        targetWidth,
        targetHeight
    );

    // Create CGImage from cropped region
    CGImageRef cgImage = [_ciContext createCGImage:scaledImage fromRect:cropRect];

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    if (!cgImage) {
        NSLog(@"[ViroFrameStream DEBUG] encodeJPEGWithCrop: Failed to create CGImage");
        return nil;
    }

    UIImage *uiImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);

    NSData *jpegData = UIImageJPEGRepresentation(uiImage, quality);
    if (!jpegData) {
        NSLog(@"[ViroFrameStream DEBUG] encodeJPEGWithCrop: Failed to encode JPEG");
        return nil;
    }

    VROJpegEncodeResult *result = [[VROJpegEncodeResult alloc] init];
    result.jpegData = jpegData;
    result.scale = scale;
    result.cropX = cropX;
    result.cropY = cropY;

    return result;
}

#pragma mark - Frame Retrieval

- (VROFrameEntry *)frameEntryForId:(NSString *)frameId {
    return [_ringBuffer entryForFrameId:frameId];
}

#pragma mark - Session Management

- (void)handleSessionReset {
    [_ringBuffer incrementSessionId];
}

@end
