//
//  VROFrameRingBuffer.h
//  ViroReact
//
//  Ring buffer for storing AR frame metadata keyed by frameId.
//  Used by VROFrameCaptureService to store capture-time data for
//  deferred 2D→3D detection resolution.
//
//  Copyright © 2024 Viro Media. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * VROFrameEntry stores all capture-time data needed for deferred 2D→3D mapping.
 * This allows accurate detection resolution even when Gemini responds after
 * the camera has moved.
 */
@interface VROFrameEntry : NSObject

/// Unique identifier for this frame capture
@property (nonatomic, copy) NSString *frameId;

/// ARFrame timestamp
@property (nonatomic, assign) double timestamp;

/// Session ID (increments on AR session reset/relocalization)
@property (nonatomic, assign) NSInteger sessionId;

/// Camera-to-world transform at capture time
@property (nonatomic, assign) simd_float4x4 cameraToWorld;

#pragma mark - JPEG-Space Data

/// Camera intrinsics mapped to JPEG dimensions WITH crop offsets applied
/// fx' = fx * scale, fy' = fy * scale
/// cx' = (cx * scale) - cropX, cy' = (cy * scale) - cropY
@property (nonatomic, assign) matrix_float3x3 intrinsicsJPEG;

/// JPEG output dimensions (exact target size after scale+crop)
@property (nonatomic, assign) CGSize jpegSize;

#pragma mark - AR Image Space Data

/// Original AR camera intrinsics (unmodified)
@property (nonatomic, assign) matrix_float3x3 intrinsicsAR;

/// AR image dimensions (from CVPixelBuffer, single source of truth)
@property (nonatomic, assign) CGSize arImageSize;

#pragma mark - Coordinate Transform

/// Transform: JPEG normalized UV (0-1) → AR image normalized UV (0-1)
/// Encodes scale + crop mapping. Use for depth sampling.
/// Formula: ar_uv = jpeg_uv * [a 0; 0 d] + [tx ty]
/// where a = targetWidth / (scale * arWidth), tx = cropX / (scale * arWidth)
@property (nonatomic, assign) CGAffineTransform jpegToARTransform;

#pragma mark - Crop Info (for debugging/advanced use)

/// Crop offset X in SCALED pixels (same as JPEG pixels), NOT source/AR pixels
@property (nonatomic, assign) float cropX;

/// Crop offset Y in SCALED pixels (same as JPEG pixels), NOT source/AR pixels
@property (nonatomic, assign) float cropY;

/// Scale factor used (MAX of scaleX/scaleY for "cover" behavior)
@property (nonatomic, assign) float scale;

#pragma mark - Portrait Orientation

/// Whether the JPEG was rotated 90° CCW for portrait display
/// When true, JS receives portrait coordinates that must be mapped back to landscape
@property (nonatomic, assign) BOOL rotatedToPortrait;

#pragma mark - JPEG Data

/// Encoded JPEG data (base64 encoded for JS event)
@property (nonatomic, strong, nullable) NSData *jpegData;

#pragma mark - Hi-Res Variant (Optional, shallow retention)

/// High-resolution JPEG of the SAME frame (same aspect, same crop
/// proportions — jpegToARTransform is identical; only dimensions and
/// intrinsics differ). Kept only for the most recent hiResRingDepth
/// frames: recon banking pulls the latest frame, so a shallow window
/// bounds memory (~400KB x depth) while the small JPEG ring stays deep.
@property (nonatomic, strong, nullable) NSData *hiResJpegData;

/// Hi-res output dimensions (portrait, post-rotation)
@property (nonatomic, assign) CGSize hiResSize;

/// Hi-res JPEG-space intrinsics (LANDSCAPE space, like intrinsicsJPEG)
@property (nonatomic, assign) matrix_float3x3 hiResIntrinsicsJPEG;

#pragma mark - Exposure

/// ARCamera exposure duration (seconds) — the motion-blur signal.
/// Long exposures in dim rooms are what smear texture bakes.
@property (nonatomic, assign) double exposureDuration;

#pragma mark - Lighting stats (luma histogram of the AR frame)

/// YES when the luma histogram was computed for this frame.
@property (nonatomic, assign) BOOL hasLightStats;
/// Mean luma, normalized 0-1 over the format's nominal range.
@property (nonatomic, assign) float lumaMean;
/// 5th / 95th percentile luma, normalized 0-1.
@property (nonatomic, assign) float lumaP05;
@property (nonatomic, assign) float lumaP95;
/// Fraction of sampled pixels at/above the clip threshold (blown highlights).
@property (nonatomic, assign) float clippedFraction;
/// Fraction of sampled pixels at/below the crush threshold (lost shadows).
@property (nonatomic, assign) float crushedFraction;
/// ARCamera exposureOffset (EV from calibrated) — darkness strain signal.
@property (nonatomic, assign) double exposureOffset;
/// ARKit light estimate riders (0 when no estimate).
@property (nonatomic, assign) float ambientIntensity;
@property (nonatomic, assign) float ambientColorTemperature;

#pragma mark - LiDAR Depth (Optional)

/// LiDAR depth buffer for this frame (if available on Pro devices)
/// NOTE: Depth is aligned to AR image space, NOT JPEG space!
/// Must use jpegToARTransform to map JPEG UV → AR UV before sampling.
@property (nonatomic, assign, nullable) CVPixelBufferRef depthBuffer;

/// LiDAR depth confidence (ARConfidenceLevel per pixel, uint8), deep copy.
/// Same dimensions as depthBuffer. NULL when unavailable.
@property (nonatomic, assign, nullable) CVPixelBufferRef confidenceBuffer;

/// Depth buffer dimensions
@property (nonatomic, assign) CGSize depthBufferSize;

#pragma mark - Feature Points (Optional, for fallback)

/// Feature points captured at frame time, packed as simd_float3 array
/// Used as fallback when LiDAR and raycast both fail
@property (nonatomic, strong, nullable) NSData *featurePointsData;

/// Number of feature points (capped at 2000 to avoid memory issues)
@property (nonatomic, assign) NSUInteger featurePointsCount;

@end


/**
 * VROFrameRingBuffer is a thread-safe ring buffer that stores VROFrameEntry
 * objects keyed by frameId. When capacity is reached, oldest entries are evicted.
 */
@interface VROFrameRingBuffer : NSObject

/// Initialize with specified capacity (recommended: 30 frames)
- (instancetype)initWithCapacity:(NSUInteger)capacity;

/// Add a new frame entry (evicts oldest if at capacity)
- (void)addEntry:(VROFrameEntry *)entry;

/// Retrieve frame entry by frameId (returns nil if not found or evicted)
- (VROFrameEntry * _Nullable)entryForFrameId:(NSString *)frameId;

/// Increment session ID (call on AR session reset/relocalization)
- (void)incrementSessionId;

/// Current session ID
- (NSInteger)currentSessionId;

@end

NS_ASSUME_NONNULL_END
