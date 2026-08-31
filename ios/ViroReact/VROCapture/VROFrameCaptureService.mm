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
#import <ImageIO/ImageIO.h>
#import <Vision/Vision.h>
#import <atomic>

#pragma mark - Pixel Buffer Deep Copy

/**
 * Deep-copy a CVPixelBuffer into a freshly allocated buffer. Used to detach
 * LiDAR depth maps from ARKit's internal pool before long-term storage in the
 * frame ring buffer. Returns a +1 retained buffer, or NULL on failure.
 */
static CVPixelBufferRef VROCopyPixelBuffer(CVPixelBufferRef src) {
    if (!src) return NULL;
    CVPixelBufferRef dst = NULL;
    OSType fmt = CVPixelBufferGetPixelFormatType(src);
    size_t width = CVPixelBufferGetWidth(src);
    size_t height = CVPixelBufferGetHeight(src);
    CVReturn rc = CVPixelBufferCreate(kCFAllocatorDefault, width, height, fmt, NULL, &dst);
    if (rc != kCVReturnSuccess || !dst) return NULL;

    CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(dst, 0);
    if (CVPixelBufferIsPlanar(src)) {
        size_t planeCount = CVPixelBufferGetPlaneCount(src);
        for (size_t i = 0; i < planeCount; i++) {
            uint8_t *srcBase = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(src, i);
            uint8_t *dstBase = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(dst, i);
            size_t srcRowBytes = CVPixelBufferGetBytesPerRowOfPlane(src, i);
            size_t dstRowBytes = CVPixelBufferGetBytesPerRowOfPlane(dst, i);
            size_t rows = CVPixelBufferGetHeightOfPlane(src, i);
            size_t rowBytes = MIN(srcRowBytes, dstRowBytes);
            for (size_t r = 0; r < rows; r++) {
                memcpy(dstBase + r * dstRowBytes, srcBase + r * srcRowBytes, rowBytes);
            }
        }
    } else {
        uint8_t *srcBase = (uint8_t *)CVPixelBufferGetBaseAddress(src);
        uint8_t *dstBase = (uint8_t *)CVPixelBufferGetBaseAddress(dst);
        size_t srcRowBytes = CVPixelBufferGetBytesPerRow(src);
        size_t dstRowBytes = CVPixelBufferGetBytesPerRow(dst);
        size_t rowBytes = MIN(srcRowBytes, dstRowBytes);
        for (size_t r = 0; r < height; r++) {
            memcpy(dstBase + r * dstRowBytes, srcBase + r * srcRowBytes, rowBytes);
        }
    }
    CVPixelBufferUnlockBaseAddress(dst, 0);
    CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    return dst;
}

#pragma mark - Helper Class for JPEG Encode Result

@interface VROJpegEncodeResult : NSObject
@property (nonatomic, strong) NSData *jpegData;
@property (nonatomic, assign) float scale;
@property (nonatomic, assign) float cropX;
@property (nonatomic, assign) float cropY;
/// Dimensions BEFORE rotation (landscape, used for coordinate transforms)
@property (nonatomic, assign) int preRotationWidth;
@property (nonatomic, assign) int preRotationHeight;
/// Dimensions of the final JPEG (after rotation if applied)
@property (nonatomic, assign) int outputWidth;
@property (nonatomic, assign) int outputHeight;
/// Whether the image was rotated 90° CCW for portrait
@property (nonatomic, assign) BOOL rotatedToPortrait;
/// Whether jpegData actually holds HEIC bytes (HEIC requested + supported)
@property (nonatomic, assign) BOOL isHeic;
@end

@implementation VROJpegEncodeResult
@end

#pragma mark - HEIC Encoding

/**
 * Encode a UIImage as HEIC via ImageIO (hardware encoder on A10+).
 * Returns nil when HEIC encoding is unavailable — caller falls back to JPEG.
 */
static NSData *VROEncodeHEIC(UIImage *image, float quality) {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)data, (__bridge CFStringRef)@"public.heic", 1, NULL);
    if (!dest) return nil;
    NSDictionary *opts = @{
        (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(quality)
    };
    CGImageDestinationAddImage(dest, cgImage, (__bridge CFDictionaryRef)opts);
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    return (ok && data.length > 0) ? data : nil;
}


#pragma mark - VROFrameCaptureService Implementation

@implementation VROFrameCaptureService {
    dispatch_queue_t _processingQueue;
    std::atomic<bool> _isProcessing;
    // FrameIds whose entries still hold a hi-res JPEG (oldest first).
    // Touched only on the serial _processingQueue.
    NSMutableArray<NSString *> *_hiResFrameIds;
    double _lastCaptureTime;
    CIContext *_ciContext;
    VROFrameRingBuffer *_ringBuffer;
    NSUInteger _frameCounter;
    // Unretained pointer identity of the last ARSession seen; a different
    // instance means the session was torn down and replaced -> bump the ring
    // buffer sessionId so JS invalidates stale frame references.
    uintptr_t _lastSessionPtr;

    // ── Text legibility (throttled Vision OCR) ──
    // OCR runs on its own utility queue (it takes 30-200ms; never block the
    // capture path). Latest completed sample lives in the ivars below and is
    // ONLY touched on _processingQueue — OCR completion hops there to store,
    // event building reads there. _ocrBusy/_lastOcrTime are capture-thread.
    dispatch_queue_t _ocrQueue;
    std::atomic<bool> _ocrBusy;
    double _lastOcrTime;
    BOOL _latestHasTextStats;
    int _latestTextBlockCount;
    float _latestTextMeanConfidence;
    float _latestTextMaxConfidence;
    float _latestTextMaxHeight;
    double _latestTextTimestamp;
    NSString *_latestTextFrameId;
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
        _hiResEnabled = NO;
        _hiResMaxDimension = 1920;
        _hiResQuality = 0.85f;
        _hiResRingDepth = 4;
        _hiResFrameIds = [NSMutableArray array];
        _hiResFormat = nil;  // nil == "jpeg"
        _frameCounter = 0;
        _includeImageDataInEvent = YES;
        _verboseLogging = NO;
        _lastSessionPtr = 0;

        _textLegibilityEnabled = NO;
        _textLegibilityIntervalMs = 1000;
        _ocrQueue = dispatch_queue_create(
            "com.viro.frameCaptureService.ocr", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(
            _ocrQueue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        _ocrBusy = false;
        _lastOcrTime = 0;
        _latestHasTextStats = NO;
    }
    return self;
}

- (void)onARFrame:(ARFrame *)frame session:(ARSession *)session {
    if (!_enabled || !frame) {
        return;
    }

    double timestamp = frame.timestamp;

    // Session-instance change detection: nothing in the fork calls
    // handleSessionReset from delegate callbacks (Viro's renderer owns the
    // ARSession delegate), so this pointer check is the reset signal. It runs
    // before rate limiting so a swap is never missed on a skipped frame.
    uintptr_t sessionPtr = (uintptr_t)session;
    if (_lastSessionPtr != 0 && sessionPtr != _lastSessionPtr) {
        NSLog(@"[ViroFrameStream] ARSession instance changed - bumping ring buffer sessionId");
        [self handleSessionReset];
    }
    _lastSessionPtr = sessionPtr;

    // Rate limit check
    double minInterval = 1.0 / _targetFPS;
    double elapsed = timestamp - _lastCaptureTime;
    if (elapsed < minInterval) {
        // Only log occasionally to avoid spam
        static int skipCount = 0;
        skipCount++;
        if (_verboseLogging && skipCount % 60 == 0) {
            NSLog(@"[ViroFrameStream DEBUG] Rate limit: skipped %d frames (interval=%.3fs, need=%.3fs)",
                  skipCount, elapsed, minInterval);
        }
        return;
    }

    // Busy check (non-blocking) using atomic compare-exchange
    bool expected = false;
    if (!_isProcessing.compare_exchange_strong(expected, true)) {
        if (_verboseLogging) {
            NSLog(@"[ViroFrameStream DEBUG] Busy: still processing previous frame, dropping");
        }
        return;
    }

    _lastCaptureTime = timestamp;
    if (_verboseLogging) {
        NSLog(@"[ViroFrameStream DEBUG] Capturing frame #%lu at timestamp %.3f", (unsigned long)_frameCounter, timestamp);
    }

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
    double exposureDuration = frame.camera.exposureDuration;

    // ── Lighting stats: stride-sampled luma histogram of plane 0 ──
    // ARKit delivers bi-planar YCbCr: plane 0 is already luma — no RGB
    // conversion, no allocation beyond a stack histogram. Thresholds are
    // derived from the pixel FORMAT (420f full range vs 420v video range);
    // assuming full range would make a video-range buffer read as "never
    // clipped, always slightly crushed".
    BOOL hasLightStats = NO;
    float lumaMean = 0, lumaP05 = 0, lumaP95 = 0, clippedFraction = 0, crushedFraction = 0;
    float sharpness = 0;
    {
        OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
        BOOL fullRange = (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
        if (fullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            const uint8_t *luma = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            if (luma) {
                size_t lw = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
                size_t lh = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
                size_t lbpr = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
                uint32_t hist[256] = {0};
                uint32_t samples = 0;
                // Laplacian variance rides the same sampled walk: cross
                // neighbors at ±1 FULL-RES pixel around each stride-8 sample.
                // Motion blur and defocus both crush high-frequency energy,
                // so this is the direct blur measurement (exposureDuration
                // is only a proxy). Units: squared 8-bit luma.
                double lapSum = 0, lapSum2 = 0;
                uint32_t lapN = 0;
                for (size_t r = 0; r < lh; r += 8) {
                    const uint8_t *row = luma + r * lbpr;
                    for (size_t c = 0; c < lw; c += 8) {
                        hist[row[c]]++;
                        samples++;
                        if (r >= 1 && r + 1 < lh && c >= 1 && c + 1 < lw) {
                            float lap = 4.0f * (float)row[c]
                                      - (float)row[c - 1] - (float)row[c + 1]
                                      - (float)(row - lbpr)[c] - (float)(row + lbpr)[c];
                            lapSum += lap;
                            lapSum2 += (double)lap * (double)lap;
                            lapN++;
                        }
                    }
                }
                CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
                if (lapN > 0) {
                    double lapMean = lapSum / (double)lapN;
                    sharpness = (float)MAX(0.0, lapSum2 / (double)lapN - lapMean * lapMean);
                }
                if (samples > 0) {
                    const int rangeLo = fullRange ? 0 : 16;
                    const int rangeHi = fullRange ? 255 : 235;
                    const int clipAt  = fullRange ? 250 : 230;
                    const int crushAt = fullRange ? 6 : 21;
                    const float span = (float)(rangeHi - rangeLo);
                    uint64_t sum = 0;
                    uint32_t clipped = 0, crushed = 0;
                    for (int v = 0; v < 256; v++) {
                        sum += (uint64_t)hist[v] * (uint64_t)v;
                        if (v >= clipAt) clipped += hist[v];
                        if (v <= crushAt) crushed += hist[v];
                    }
                    uint32_t p05Target = (uint32_t)(samples * 0.05);
                    uint32_t p95Target = (uint32_t)(samples * 0.95);
                    uint32_t running = 0;
                    int p05 = rangeLo, p95 = rangeHi;
                    BOOL got05 = NO;
                    for (int v = 0; v < 256; v++) {
                        running += hist[v];
                        if (!got05 && running >= p05Target) { p05 = v; got05 = YES; }
                        if (running >= p95Target) { p95 = v; break; }
                    }
                    auto norm = [&](float v) { return MAX(0.f, MIN(1.f, (v - rangeLo) / span)); };
                    lumaMean = norm((float)sum / (float)samples);
                    lumaP05 = norm((float)p05);
                    lumaP95 = norm((float)p95);
                    clippedFraction = (float)clipped / (float)samples;
                    crushedFraction = (float)crushed / (float)samples;
                    hasLightStats = YES;
                }
            } else {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            }
        }
    }
    // Free riders off the same ARFrame: auto-exposure strain and the light
    // estimate (color temperature is exposed nowhere else in the fork).
    double exposureOffset = 0;
    if (@available(iOS 13.0, *)) {
        exposureOffset = frame.camera.exposureOffset;
    }
    float ambientIntensity = frame.lightEstimate ? (float)frame.lightEstimate.ambientIntensity : 0.f;
    float ambientColorTemperature = frame.lightEstimate ? (float)frame.lightEstimate.ambientColorTemperature : 0.f;

    // V2.3 FIX: Use CVPixelBuffer dimensions as SINGLE SOURCE OF TRUTH
    // This ensures arImageSize matches exactly what we encode
    size_t srcWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t srcHeight = CVPixelBufferGetHeight(pixelBuffer);
    CGSize arImageSize = CGSizeMake(srcWidth, srcHeight);

    // Capture LiDAR depth if available (iOS 14.0+ on Pro devices)
    CVPixelBufferRef depthBuffer = nil;
    CVPixelBufferRef confidenceBuffer = nil;
    CGSize depthBufferSize = CGSizeZero;
    if (@available(iOS 14.0, *)) {
        if (frame.sceneDepth.depthMap) {
            depthBuffer = frame.sceneDepth.depthMap;
            CVPixelBufferRetain(depthBuffer);
            depthBufferSize = CGSizeMake(
                CVPixelBufferGetWidth(depthBuffer),
                CVPixelBufferGetHeight(depthBuffer)
            );
            // Per-pixel ARConfidenceLevel (uint8) — lets the server weight
            // or reject unreliable depth (glass, dark corners) in the
            // occlusion test and any future TSDF fusion.
            if (frame.sceneDepth.confidenceMap) {
                confidenceBuffer = frame.sceneDepth.confidenceMap;
                CVPixelBufferRetain(confidenceBuffer);
            }
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

    // ── Throttled on-device OCR (text legibility) ──
    // Runs on its own utility queue against a +1 retained camera buffer;
    // results land on _processingQueue (sole owner of the _latestText*
    // ivars) and are written back onto the sampled frame's ring entry.
    if (_textLegibilityEnabled) {
        double ocrIntervalSec = MAX(_textLegibilityIntervalMs, 100) / 1000.0;
        bool ocrExpected = false;
        if (timestamp - _lastOcrTime >= ocrIntervalSec &&
            _ocrBusy.compare_exchange_strong(ocrExpected, true)) {
            _lastOcrTime = timestamp;
            CVPixelBufferRetain(pixelBuffer);
            CVPixelBufferRef ocrBuffer = pixelBuffer;
            NSString *ocrFrameId = frameId;
            BOOL ocrVerbose = _verboseLogging;
            dispatch_async(_ocrQueue, ^{
                [self runTextLegibilityOnBuffer:ocrBuffer
                                        frameId:ocrFrameId
                                      timestamp:timestamp
                                        verbose:ocrVerbose];
            });
        }
    }

    // Capture config values for async block
    int targetWidth = _targetWidth;
    int targetHeight = _targetHeight;
    float jpegQuality = _jpegQuality;
    BOOL hiResEnabled = _hiResEnabled;
    int hiResMaxDimension = _hiResMaxDimension;
    float hiResQuality = _hiResQuality;
    int hiResRingDepth = _hiResRingDepth;
    BOOL hiResWantHeic = [_hiResFormat isEqualToString:@"heic"];
    NSInteger sessionId = [_ringBuffer currentSessionId];
    BOOL includeImage = _includeImageDataInEvent;
    BOOL verbose = _verboseLogging;

    // Process on background queue
    dispatch_async(_processingQueue, ^{
        @autoreleasepool {
            // 1. Encode JPEG with scale+crop (EXACT target dimensions)
            VROJpegEncodeResult *encodeResult = [self encodeJPEGWithCrop:pixelBuffer
                                                            targetWidth:targetWidth
                                                           targetHeight:targetHeight
                                                                quality:jpegQuality];

            // Hi-res variant of the SAME frame, while the full-res camera
            // buffer is still in hand. Target dims share the small stream's
            // aspect, so the cover-crop is proportional: jpegToARTransform
            // is identical and only intrinsics/dimensions differ.
            VROJpegEncodeResult *hiResResult = nil;
            if (hiResEnabled && encodeResult && encodeResult.jpegData) {
                float longSide = (float)MAX(targetWidth, targetHeight);
                float k = (float)hiResMaxDimension / MAX(longSide, 1.0f);
                if (k > 1.01f) {
                    int hiW = (int)lroundf(targetWidth * k);
                    int hiH = (int)lroundf(targetHeight * k);
                    hiResResult = [self encodeWithCrop:pixelBuffer
                                           targetWidth:hiW
                                          targetHeight:hiH
                                               quality:hiResQuality
                                               useHeic:hiResWantHeic];
                }
            }
            CVPixelBufferRelease(pixelBuffer);

            if (!encodeResult || !encodeResult.jpegData) {
                NSLog(@"[ViroFrameStream DEBUG] JPEG encode FAILED for frame %@", frameId);
                if (depthBuffer) CVPixelBufferRelease(depthBuffer);
                if (confidenceBuffer) CVPixelBufferRelease(confidenceBuffer);
                self->_isProcessing = false;
                return;
            }

            if (verbose) NSLog(@"[ViroFrameStream DEBUG] JPEG encoded: %lu bytes, scale=%.3f, crop=(%.1f, %.1f), preRot=%dx%d, output=%dx%d, rotated=%@",
                  (unsigned long)encodeResult.jpegData.length, encodeResult.scale,
                  encodeResult.cropX, encodeResult.cropY,
                  encodeResult.preRotationWidth, encodeResult.preRotationHeight,
                  encodeResult.outputWidth, encodeResult.outputHeight,
                  encodeResult.rotatedToPortrait ? @"YES" : @"NO");

            float scale = encodeResult.scale;
            float cropX = encodeResult.cropX;
            float cropY = encodeResult.cropY;
            // Pre-rotation (landscape) dimensions - used for intrinsics and transforms
            int preRotationWidth = encodeResult.preRotationWidth;
            int preRotationHeight = encodeResult.preRotationHeight;
            // Post-rotation (portrait) dimensions - what JS receives
            int outputWidth = encodeResult.outputWidth;
            int outputHeight = encodeResult.outputHeight;
            BOOL rotatedToPortrait = encodeResult.rotatedToPortrait;

            // 2. Calculate JPEG-space intrinsics WITH CROP OFFSETS
            // These are in LANDSCAPE space (pre-rotation) for coordinate resolution
            // fx' = fx * scale
            // fy' = fy * scale
            // cx' = (cx * scale) - cropX   <-- CRITICAL: subtract crop offset!
            // cy' = (cy * scale) - cropY
            matrix_float3x3 intrinsicsJPEG = arIntrinsics;
            intrinsicsJPEG.columns[0][0] *= scale;  // fx
            intrinsicsJPEG.columns[1][1] *= scale;  // fy
            intrinsicsJPEG.columns[2][0] = arIntrinsics.columns[2][0] * scale - cropX;  // cx
            intrinsicsJPEG.columns[2][1] = arIntrinsics.columns[2][1] * scale - cropY;  // cy

            // 3. Calculate jpegToARTransform: LANDSCAPE JPEG UV (0-1) → AR image UV (0-1)
            // NOTE: This transform is in LANDSCAPE space (pre-rotation).
            // The resolver first converts portrait→landscape coords before applying this.
            //
            // Pipeline (forward):
            //   scaled_px = AR_px * scale
            //   JPEG_px = scaled_px - crop  (center crop)
            //
            // Inverse (what we need):
            //   scaled_px = JPEG_px + crop
            //   AR_px = scaled_px / scale = (JPEG_px + crop) / scale
            //
            // In UV space (using pre-rotation/landscape dimensions):
            //   JPEG_px = jpegU * preRotationWidth
            //   AR_px = (JPEG_px + cropX) / scale
            //   AR_u = AR_px / arWidth = (jpegU * preRotationWidth + cropX) / (scale * arWidth)
            //        = jpegU * (preRotationWidth / (scale * arWidth)) + cropX / (scale * arWidth)
            //
            // So the transform coefficients are:
            //   a = preRotationWidth / (scale * arWidth)
            //   d = preRotationHeight / (scale * arHeight)
            //   tx = cropX / (scale * arWidth)
            //   ty = cropY / (scale * arHeight)
            float scaledARWidth = scale * arImageSize.width;
            float scaledARHeight = scale * arImageSize.height;

            float jpegToAR_scaleX = (float)preRotationWidth / scaledARWidth;
            float jpegToAR_scaleY = (float)preRotationHeight / scaledARHeight;
            float jpegToAR_offsetX = cropX / scaledARWidth;
            float jpegToAR_offsetY = cropY / scaledARHeight;

            // CGAffineTransform: result = input * [a b; c d] + [tx ty]
            CGAffineTransform jpegToARTransform = CGAffineTransformMake(
                jpegToAR_scaleX, 0,                    // a, b
                0, jpegToAR_scaleY,                    // c, d
                jpegToAR_offsetX, jpegToAR_offsetY    // tx, ty
            );

            // 4. Create ring buffer entry.
            // Deep-copy the depth map first: frame.sceneDepth.depthMap belongs
            // to ARKit's fixed internal buffer pool, and the ring holds entries
            // for up to ~30s -- retaining pool buffers that long can starve the
            // pool and stall depth production. The copy (~200 KB) frees ARKit's
            // buffer within milliseconds of capture.
            CVPixelBufferRef depthCopy = NULL;
            if (depthBuffer) {
                depthCopy = VROCopyPixelBuffer(depthBuffer);
                CVPixelBufferRelease(depthBuffer);
            }
            CVPixelBufferRef confidenceCopy = NULL;
            if (confidenceBuffer) {
                confidenceCopy = VROCopyPixelBuffer(confidenceBuffer);
                CVPixelBufferRelease(confidenceBuffer);
            }

            VROFrameEntry *entry = [[VROFrameEntry alloc] init];
            entry.frameId = frameId;
            entry.timestamp = timestamp;
            entry.sessionId = sessionId;
            entry.cameraToWorld = cameraTransform;

            // Store LANDSCAPE intrinsics (pre-rotation) for coordinate resolution
            // Even though JS receives portrait image, intrinsics are in landscape space
            entry.intrinsicsJPEG = intrinsicsJPEG;
            // Store PORTRAIT dimensions (what JS sees) - for display reference
            entry.jpegSize = CGSizeMake(outputWidth, outputHeight);
            entry.rotatedToPortrait = rotatedToPortrait;

            entry.intrinsicsAR = arIntrinsics;
            entry.arImageSize = arImageSize;

            entry.jpegToARTransform = jpegToARTransform;
            entry.cropX = cropX;
            entry.cropY = cropY;
            entry.scale = scale;

            entry.jpegData = encodeResult.jpegData;
            entry.depthBuffer = depthCopy;  // Transfer ownership of the copy
            entry.depthBufferSize = depthBufferSize;

            entry.featurePointsData = featurePointsData;
            entry.featurePointsCount = featurePointsCount;
            entry.exposureDuration = exposureDuration;
            entry.confidenceBuffer = confidenceCopy;  // Transfer ownership
            entry.hasLightStats = hasLightStats;
            entry.lumaMean = lumaMean;
            entry.lumaP05 = lumaP05;
            entry.lumaP95 = lumaP95;
            entry.clippedFraction = clippedFraction;
            entry.crushedFraction = crushedFraction;
            entry.exposureOffset = exposureOffset;
            entry.ambientIntensity = ambientIntensity;
            entry.ambientColorTemperature = ambientColorTemperature;
            entry.sharpness = sharpness;

            if (hiResResult && hiResResult.jpegData) {
                entry.hiResJpegData = hiResResult.jpegData;
                entry.hiResFormat = hiResResult.isHeic ? @"heic" : @"jpeg";
                entry.hiResSize = CGSizeMake(hiResResult.outputWidth, hiResResult.outputHeight);
                matrix_float3x3 hiResIntrinsics = arIntrinsics;
                hiResIntrinsics.columns[0][0] *= hiResResult.scale;
                hiResIntrinsics.columns[1][1] *= hiResResult.scale;
                hiResIntrinsics.columns[2][0] = arIntrinsics.columns[2][0] * hiResResult.scale - hiResResult.cropX;
                hiResIntrinsics.columns[2][1] = arIntrinsics.columns[2][1] * hiResResult.scale - hiResResult.cropY;
                entry.hiResIntrinsicsJPEG = hiResIntrinsics;
            }

            [self->_ringBuffer addEntry:entry];

            // Shallow hi-res retention: recon banking always pulls the
            // LATEST frame, so only the newest few need to stay heavy.
            if (entry.hiResJpegData) {
                [self->_hiResFrameIds addObject:frameId];
                while ((int)self->_hiResFrameIds.count > MAX(hiResRingDepth, 1)) {
                    NSString *oldId = self->_hiResFrameIds.firstObject;
                    [self->_hiResFrameIds removeObjectAtIndex:0];
                    VROFrameEntry *oldEntry = [self->_ringBuffer entryForFrameId:oldId];
                    oldEntry.hiResJpegData = nil;
                }
            }
            if (verbose) {
                NSLog(@"[ViroFrameStream DEBUG] Stored frame %@ in ring buffer (sessionId=%ld)", frameId, (long)sessionId);
            }

            // 5. Build event payload (no depth data - too large)
            NSMutableDictionary *event = [NSMutableDictionary dictionary];
            event[@"frameId"] = frameId;
            event[@"timestamp"] = @(timestamp);
            event[@"sessionId"] = @(sessionId);
            if (includeImage) {
                event[@"imageData"] = [encodeResult.jpegData base64EncodedStringWithOptions:0];
            }
            // Send portrait dimensions (what JS sees after rotation)
            event[@"width"] = @(outputWidth);
            event[@"height"] = @(outputHeight);
            event[@"rotatedToPortrait"] = @(rotatedToPortrait);
            event[@"exposureDuration"] = @(exposureDuration);
            // Lighting stats (optional — older JS just sees undefined).
            if (hasLightStats) {
                event[@"lumaMean"] = @(lumaMean);
                event[@"lumaP05"] = @(lumaP05);
                event[@"lumaP95"] = @(lumaP95);
                event[@"clippedFraction"] = @(clippedFraction);
                event[@"crushedFraction"] = @(crushedFraction);
                event[@"sharpness"] = @(sharpness);
            }
            event[@"exposureOffset"] = @(exposureOffset);
            if (ambientIntensity > 0) {
                event[@"ambientIntensity"] = @(ambientIntensity);
                event[@"ambientColorTemperature"] = @(ambientColorTemperature);
            }
            // Latest OCR sample (throttled — usually a slightly older frame;
            // textSampleAgeMs says how much older). Read on _processingQueue,
            // the sole owner of the _latestText* ivars.
            if (self->_latestHasTextStats) {
                event[@"textBlockCount"] = @(self->_latestTextBlockCount);
                event[@"textMeanConfidence"] = @(self->_latestTextMeanConfidence);
                event[@"textMaxConfidence"] = @(self->_latestTextMaxConfidence);
                event[@"textMaxHeight"] = @(self->_latestTextMaxHeight);
                event[@"textSampleFrameId"] = self->_latestTextFrameId ?: @"";
                event[@"textSampleAgeMs"] = @(MAX(0.0, (timestamp - self->_latestTextTimestamp) * 1000.0));
            }

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
                if (verbose) {
                    NSLog(@"[ViroFrameStream DEBUG] Emitting frame %@ to JS (%dx%d portrait, tracking=%@)",
                          frameId, outputWidth, outputHeight, event[@"trackingState"]);
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onFrameReady(event);
                });
            } else if (verbose) {
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
    return [self encodeWithCrop:pixelBuffer
                    targetWidth:targetWidth
                   targetHeight:targetHeight
                        quality:quality
                        useHeic:NO];
}

- (VROJpegEncodeResult *)encodeWithCrop:(CVPixelBufferRef)pixelBuffer
                            targetWidth:(int)targetWidth
                           targetHeight:(int)targetHeight
                                quality:(float)quality
                                useHeic:(BOOL)useHeic {

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

    // User passes PORTRAIT dimensions (e.g., 720x1280) as the desired final output.
    // Since we rotate 90° CCW at the end, we need to crop LANDSCAPE first.
    // Pre-rotation crop dimensions are swapped: cropWidth=targetHeight, cropHeight=targetWidth
    // After 90° CCW rotation: (cropWidth x cropHeight) → (targetWidth x targetHeight)
    int cropWidth = targetHeight;   // Landscape width = portrait height
    int cropHeight = targetWidth;   // Landscape height = portrait width

    // Use MAX scale (cover) to ensure we can crop to exact target size
    float scaleX = (float)cropWidth / srcWidth;
    float scaleY = (float)cropHeight / srcHeight;
    float scale = MAX(scaleX, scaleY);  // COVER, not fit!

    // Scale the image
    CIImage *scaledImage = [ciImage imageByApplyingTransform:
                           CGAffineTransformMakeScale(scale, scale)];

    // Calculate crop rect (center crop)
    CGRect scaledExtent = scaledImage.extent;
    float scaledWidth = scaledExtent.size.width;
    float scaledHeight = scaledExtent.size.height;

    // Crop offsets in SCALED space (landscape pre-rotation)
    float cropX = (scaledWidth - cropWidth) / 2.0f;
    float cropY = (scaledHeight - cropHeight) / 2.0f;

    // Crop rect in scaled image coordinates (landscape, pre-rotation)
    CGRect cropRect = CGRectMake(
        scaledExtent.origin.x + cropX,
        scaledExtent.origin.y + cropY,
        cropWidth,
        cropHeight
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

    // Rotate 90° CCW for portrait orientation
    // ARKit captures in landscape right; rotating CCW gives correct portrait view
    UIImage *rotatedImage = [self rotateImage:uiImage byDegrees:90];
    if (!rotatedImage) {
        NSLog(@"[ViroFrameStream DEBUG] encodeJPEGWithCrop: Failed to rotate image");
        return nil;
    }

    NSData *encodedData = nil;
    BOOL isHeic = NO;
    if (useHeic) {
        encodedData = VROEncodeHEIC(rotatedImage, quality);
        isHeic = (encodedData != nil);
    }
    if (!encodedData) {
        encodedData = UIImageJPEGRepresentation(rotatedImage, quality);
    }
    if (!encodedData) {
        NSLog(@"[ViroFrameStream DEBUG] encodeWithCrop: Failed to encode image");
        return nil;
    }

    VROJpegEncodeResult *result = [[VROJpegEncodeResult alloc] init];
    result.jpegData = encodedData;
    result.isHeic = isHeic;
    result.scale = scale;
    result.cropX = cropX;
    result.cropY = cropY;
    // Pre-rotation (landscape) dimensions - used for coordinate transforms
    result.preRotationWidth = cropWidth;
    result.preRotationHeight = cropHeight;
    // After 90° CCW rotation of (cropWidth x cropHeight), output is (targetWidth x targetHeight)
    // This matches the user's requested portrait dimensions
    result.outputWidth = targetWidth;   // User's requested portrait width
    result.outputHeight = targetHeight; // User's requested portrait height
    result.rotatedToPortrait = YES;

    return result;
}

#pragma mark - Image Rotation

/**
 * Rotate UIImage by specified degrees counter-clockwise.
 * For portrait correction, we rotate 90° CCW (which is 270° CW or -90° in UIKit terms).
 */
- (UIImage *)rotateImage:(UIImage *)image byDegrees:(CGFloat)degrees {
    if (!image) return nil;

    // 90° CCW = -90° in standard rotation = 270° CW
    // UIImage uses a coordinate system where positive rotation is CCW
    CGFloat radians = degrees * M_PI / 180.0;

    CGSize originalSize = image.size;
    // For 90° rotation, swap width and height
    CGSize rotatedSize = CGSizeMake(originalSize.height, originalSize.width);

    UIGraphicsBeginImageContextWithOptions(rotatedSize, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }

    // Move origin to center of rotated canvas
    CGContextTranslateCTM(context, rotatedSize.width / 2, rotatedSize.height / 2);

    // Rotate CCW (positive radians in UIKit coordinate system)
    CGContextRotateCTM(context, radians);

    // Draw image centered at origin
    [image drawInRect:CGRectMake(-originalSize.width / 2, -originalSize.height / 2,
                                  originalSize.width, originalSize.height)];

    UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return rotatedImage;
}

#pragma mark - Text Legibility (Vision OCR)

/**
 * Fast-path Vision text recognition on a +1 retained camera buffer.
 * Runs on _ocrQueue; stores the completed sample via _processingQueue
 * (sole owner of the _latestText* ivars) and writes it back onto the
 * sampled frame's ring entry when that entry still exists.
 */
- (void)runTextLegibilityOnBuffer:(CVPixelBufferRef)buffer
                          frameId:(NSString *)frameId
                        timestamp:(double)timestamp
                          verbose:(BOOL)verbose {
    int blockCount = 0;
    float meanConf = 0, maxConf = 0, maxHeight = 0;
    BOOL ok = NO;
    if (@available(iOS 13.0, *)) {
        @autoreleasepool {
            VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
            request.recognitionLevel = VNRequestTextRecognitionLevelFast;
            request.usesLanguageCorrection = NO;
            // The camera buffer is landscape (sensor-native); .Right presents
            // it upright for a portrait-held device — the same 90° the JPEG
            // rotation applies. Bounding boxes come back in UPRIGHT space.
            VNImageRequestHandler *handler =
                [[VNImageRequestHandler alloc] initWithCVPixelBuffer:buffer
                                                         orientation:kCGImagePropertyOrientationRight
                                                             options:@{}];
            NSError *error = nil;
            if ([handler performRequests:@[request] error:&error]) {
                ok = YES;
                float confSum = 0;
                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [obs topCandidates:1].firstObject;
                    if (!top) continue;
                    blockCount++;
                    float conf = (float)top.confidence;
                    confSum += conf;
                    maxConf = MAX(maxConf, conf);
                    maxHeight = MAX(maxHeight, (float)obs.boundingBox.size.height);
                }
                meanConf = blockCount > 0 ? confSum / (float)blockCount : 0.f;
            } else if (verbose) {
                NSLog(@"[ViroFrameStream DEBUG] Text legibility OCR failed: %@", error);
            }
        }
    }
    CVPixelBufferRelease(buffer);
    self->_ocrBusy = false;
    if (!ok) return;
    if (verbose) {
        NSLog(@"[ViroFrameStream DEBUG] OCR frame %@: %d blocks, meanConf=%.2f maxH=%.3f",
              frameId, blockCount, meanConf, maxHeight);
    }
    dispatch_async(_processingQueue, ^{
        self->_latestHasTextStats = YES;
        self->_latestTextBlockCount = blockCount;
        self->_latestTextMeanConfidence = meanConf;
        self->_latestTextMaxConfidence = maxConf;
        self->_latestTextMaxHeight = maxHeight;
        self->_latestTextTimestamp = timestamp;
        self->_latestTextFrameId = frameId;
        VROFrameEntry *entry = [self->_ringBuffer entryForFrameId:frameId];
        if (entry) {
            entry.hasTextStats = YES;
            entry.textBlockCount = blockCount;
            entry.textMeanConfidence = meanConf;
            entry.textMaxConfidence = maxConf;
            entry.textMaxHeight = maxHeight;
        }
    });
}

#pragma mark - Frame Retrieval

- (VROFrameEntry *)frameEntryForId:(NSString *)frameId {
    return [_ringBuffer entryForFrameId:frameId];
}

- (NSDictionary *)frameDataForId:(NSString *)frameId {
    VROFrameEntry *entry = [_ringBuffer entryForFrameId:frameId];
    if (!entry || !entry.jpegData) {
        return nil;
    }
    return @{
        @"frameId": entry.frameId,
        @"timestamp": @(entry.timestamp),
        @"sessionId": @(entry.sessionId),
        @"imageData": [entry.jpegData base64EncodedStringWithOptions:0],
        @"width": @((int)entry.jpegSize.width),
        @"height": @((int)entry.jpegSize.height),
    };
}

static NSArray *VROFlattenIntrinsicsRowMajor(matrix_float3x3 m) {
    // Row-major flat 9: [fx, 0, cx, 0, fy, cy, 0, 0, 1] — the layout the
    // app banks and the reconstruction service parses.
    return @[
        @(m.columns[0][0]), @(m.columns[1][0]), @(m.columns[2][0]),
        @(m.columns[0][1]), @(m.columns[1][1]), @(m.columns[2][1]),
        @(m.columns[0][2]), @(m.columns[1][2]), @(m.columns[2][2]),
    ];
}

- (NSDictionary *)frameDataForId:(NSString *)frameId
                         options:(NSDictionary *)options {
    VROFrameEntry *entry = [_ringBuffer entryForFrameId:frameId];
    if (!entry) {
        return nil;
    }
    BOOL wantHiRes = [options[@"variant"] isEqual:@"hires"];
    BOOL includeDepth = [options[@"includeDepth"] boolValue];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"frameId"] = entry.frameId;
    result[@"timestamp"] = @(entry.timestamp);
    result[@"sessionId"] = @(entry.sessionId);
    result[@"exposureDuration"] = @(entry.exposureDuration);
    if (entry.hasLightStats) {
        result[@"lumaMean"] = @(entry.lumaMean);
        result[@"lumaP05"] = @(entry.lumaP05);
        result[@"lumaP95"] = @(entry.lumaP95);
        result[@"clippedFraction"] = @(entry.clippedFraction);
        result[@"crushedFraction"] = @(entry.crushedFraction);
        result[@"sharpness"] = @(entry.sharpness);
    }
    if (entry.hasTextStats) {
        result[@"textBlockCount"] = @(entry.textBlockCount);
        result[@"textMeanConfidence"] = @(entry.textMeanConfidence);
        result[@"textMaxConfidence"] = @(entry.textMaxConfidence);
        result[@"textMaxHeight"] = @(entry.textMaxHeight);
    }
    result[@"exposureOffset"] = @(entry.exposureOffset);
    if (entry.ambientIntensity > 0) {
        result[@"ambientIntensity"] = @(entry.ambientIntensity);
        result[@"ambientColorTemperature"] = @(entry.ambientColorTemperature);
    }
    result[@"rotatedToPortrait"] = @(entry.rotatedToPortrait);

    if (wantHiRes) {
        if (!entry.hiResJpegData) {
            result[@"error"] = @"hi-res variant unavailable (disabled, evicted, or frame predates hiResEnabled)";
            return result;
        }
        result[@"imageData"] = [entry.hiResJpegData base64EncodedStringWithOptions:0];
        result[@"width"] = @((int)entry.hiResSize.width);
        result[@"height"] = @((int)entry.hiResSize.height);
        result[@"intrinsics"] = VROFlattenIntrinsicsRowMajor(entry.hiResIntrinsicsJPEG);
        // "jpeg" | "heic" — what imageData actually holds. Old entries
        // (nil hiResFormat) and the small stream are always JPEG.
        result[@"format"] = entry.hiResFormat ?: @"jpeg";
    } else {
        if (!entry.jpegData) {
            result[@"error"] = @"frame JPEG evicted";
            return result;
        }
        result[@"imageData"] = [entry.jpegData base64EncodedStringWithOptions:0];
        result[@"width"] = @((int)entry.jpegSize.width);
        result[@"height"] = @((int)entry.jpegSize.height);
        result[@"intrinsics"] = VROFlattenIntrinsicsRowMajor(entry.intrinsicsJPEG);
        result[@"format"] = @"jpeg";
    }

    if (includeDepth && entry.depthBuffer) {
        // LiDAR depth, AR-image space (NOT JPEG space), row-major, no
        // padding. Sample it via jpegToARTransform + arIntrinsics — both
        // included below. Default float32 meters; depthFormat "uint16mm"
        // packs uint16 millimeters (0 = no data, clamped to 65.535m) at
        // half the bytes for upload-bound consumers.
        BOOL wantU16 = [options[@"depthFormat"] isEqual:@"uint16mm"];
        CVPixelBufferRef depth = entry.depthBuffer;
        CVPixelBufferLockBaseAddress(depth, kCVPixelBufferLock_ReadOnly);
        size_t dw = CVPixelBufferGetWidth(depth);
        size_t dh = CVPixelBufferGetHeight(depth);
        size_t stride = CVPixelBufferGetBytesPerRow(depth);
        const uint8_t *base = (const uint8_t *)CVPixelBufferGetBaseAddress(depth);
        NSMutableData *packed;
        if (wantU16) {
            packed = [NSMutableData dataWithLength:dw * dh * sizeof(uint16_t)];
            uint16_t *dst = (uint16_t *)packed.mutableBytes;
            for (size_t row = 0; row < dh; row++) {
                const float *srcRow = (const float *)(base + row * stride);
                for (size_t col = 0; col < dw; col++) {
                    float d = srcRow[col];
                    uint16_t mm = 0;
                    if (d > 0.f && isfinite(d)) {
                        float mmf = roundf(d * 1000.f);
                        mm = (uint16_t)MIN(65535.f, MAX(1.f, mmf));
                    }
                    dst[row * dw + col] = mm;
                }
            }
        } else {
            packed = [NSMutableData dataWithLength:dw * dh * sizeof(float)];
            uint8_t *dst = (uint8_t *)packed.mutableBytes;
            for (size_t row = 0; row < dh; row++) {
                memcpy(dst + row * dw * sizeof(float), base + row * stride, dw * sizeof(float));
            }
        }
        CVPixelBufferUnlockBaseAddress(depth, kCVPixelBufferLock_ReadOnly);
        result[@"depthData"] = [packed base64EncodedStringWithOptions:0];
        result[@"depthWidth"] = @((int)dw);
        result[@"depthHeight"] = @((int)dh);
        result[@"depthFormat"] = wantU16 ? @"uint16mm" : @"float32";
        // Depth confidence (ARConfidenceLevel per pixel, uint8, row-major,
        // unpadded, same dims as depthData). 0=low 1=medium 2=high.
        if (entry.confidenceBuffer) {
            CVPixelBufferRef conf = entry.confidenceBuffer;
            CVPixelBufferLockBaseAddress(conf, kCVPixelBufferLock_ReadOnly);
            size_t cw = CVPixelBufferGetWidth(conf);
            size_t ch = CVPixelBufferGetHeight(conf);
            size_t cstride = CVPixelBufferGetBytesPerRow(conf);
            const uint8_t *cbase = (const uint8_t *)CVPixelBufferGetBaseAddress(conf);
            if (cbase && cw == dw && ch == dh) {
                NSMutableData *cpacked = [NSMutableData dataWithLength:cw * ch];
                uint8_t *cdst = (uint8_t *)cpacked.mutableBytes;
                for (size_t row = 0; row < ch; row++) {
                    memcpy(cdst + row * cw, cbase + row * cstride, cw);
                }
                result[@"depthConfidenceData"] = [cpacked base64EncodedStringWithOptions:0];
            }
            CVPixelBufferUnlockBaseAddress(conf, kCVPixelBufferLock_ReadOnly);
        }
        result[@"arIntrinsics"] = VROFlattenIntrinsicsRowMajor(entry.intrinsicsAR);
        result[@"arImageWidth"] = @((int)entry.arImageSize.width);
        result[@"arImageHeight"] = @((int)entry.arImageSize.height);
        result[@"jpegToARTransform"] = @[
            @(entry.jpegToARTransform.a), @(entry.jpegToARTransform.b), @(0),
            @(entry.jpegToARTransform.c), @(entry.jpegToARTransform.d), @(0),
            @(entry.jpegToARTransform.tx), @(entry.jpegToARTransform.ty), @(1),
        ];
    }
    return result;
}

#pragma mark - Session Management

- (void)handleSessionReset {
    [_ringBuffer incrementSessionId];
}

@end
