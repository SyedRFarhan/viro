//
//  VROFrameCaptureService.h
//  ViroReact
//
//  Main service for AR frame capture, JPEG encoding, and ring buffer management.
//  Handles rate limiting, scale+crop encoding for exact target dimensions, and
//  capture-time data storage for deferred 2D→3D detection resolution.
//
//  Copyright © 2024 Viro Media. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ARKit/ARKit.h>

@class VROFrameEntry;

NS_ASSUME_NONNULL_BEGIN

/**
 * VROFrameCaptureService captures AR frames at a configurable rate,
 * encodes them as JPEG with exact target dimensions (scale+crop),
 * and stores capture-time metadata in a ring buffer for deferred
 * detection resolution.
 *
 * Key Features:
 * - Non-blocking: drops frames rather than queuing
 * - Rate limited: configurable 1-5 FPS
 * - Scale+crop: exact target dimensions via "cover" scaling
 * - Capture-time storage: pose, intrinsics, depth, feature points
 * - V2.3 fixes: non-blocking JS delivery, single source of truth for dimensions
 */
@interface VROFrameCaptureService : NSObject

#pragma mark - Configuration Properties

/// Enable/disable frame capture
@property (nonatomic, assign) BOOL enabled;

/// Target output width in pixels (default: 640)
@property (nonatomic, assign) int targetWidth;

/// Target output height in pixels (default: 480)
@property (nonatomic, assign) int targetHeight;

/// Target frames per second (1-5, default: 5)
@property (nonatomic, assign) float targetFPS;

/// JPEG compression quality (0.0-1.0, default: 0.7)
@property (nonatomic, assign) float jpegQuality;

#pragma mark - Hi-Res Variant (recon/texturing keyframes)

/// Also encode a high-resolution JPEG of each streamed frame (default: NO).
/// Same aspect and crop proportions as the small stream; retained only for
/// the newest hiResRingDepth frames.
@property (nonatomic, assign) BOOL hiResEnabled;

/// Long-side cap for the hi-res variant (default: 1920)
@property (nonatomic, assign) int hiResMaxDimension;

/// JPEG quality for the hi-res variant (default: 0.85)
@property (nonatomic, assign) float hiResQuality;

/// How many recent frames keep their hi-res JPEG (default: 4)
@property (nonatomic, assign) int hiResRingDepth;

/// Container format for the hi-res variant: @"jpeg" (default) or @"heic".
/// HEIC halves bytes at equal quality (hardware encoder); silently falls
/// back to JPEG when HEIC encoding is unavailable. The format actually
/// used is reported per frame in getFrameData's `format` field.
@property (nonatomic, copy, nullable) NSString *hiResFormat;

#pragma mark - Text Legibility (throttled on-device OCR)

/// Run Vision text recognition (fast path, no language correction) on a
/// throttled subset of captured frames and attach legibility stats to
/// frame events + ring entries (default: NO). iOS 13+; no-op below.
@property (nonatomic, assign) BOOL textLegibilityEnabled;

/// Minimum interval between OCR samples in milliseconds (default: 1000).
@property (nonatomic, assign) int textLegibilityIntervalMs;

/// When YES (default), each onFrameReady event carries the base64 JPEG in
/// `imageData`. When NO, events are metadata-only (~300 bytes) and consumers
/// fetch image bytes on demand via frameDataForId: -- only frames that are
/// actually sent pay the bridge cost.
@property (nonatomic, assign) BOOL includeImageDataInEvent;

/// Per-frame debug logging (default: NO). The hot path logs several lines per
/// captured frame; keep this off outside active native debugging.
@property (nonatomic, assign) BOOL verboseLogging;

#pragma mark - Callback

/// Called when a frame is ready, with event dictionary suitable for JS
/// Contains: frameId, timestamp, sessionId, imageData (base64), width, height,
/// intrinsics, cameraToWorld, jpegToARTransform, trackingState
@property (nonatomic, copy, nullable) void (^onFrameReady)(NSDictionary *frameData);

#pragma mark - Initialization

/// Initialize with ring buffer capacity (recommended: 30 frames)
- (instancetype)initWithRingBufferCapacity:(NSUInteger)capacity;

#pragma mark - Frame Processing

/// Process an AR frame (call from render loop)
/// Handles rate limiting and non-blocking capture
- (void)onARFrame:(ARFrame *)frame session:(ARSession *)session;

#pragma mark - Frame Retrieval

/// Retrieve frame entry by ID for detection resolution
/// Returns nil if frame not found or evicted from ring buffer
- (VROFrameEntry * _Nullable)frameEntryForId:(NSString *)frameId;

/// On-demand image fetch for metadata-only streaming: returns the frame's
/// base64 JPEG plus identifying metadata, or nil if the frame was evicted.
- (NSDictionary * _Nullable)frameDataForId:(NSString *)frameId;

/// Frame data with options:
///   variant: "hires" -> the hi-res JPEG (error if evicted/never encoded)
///   includeDepth: YES -> LiDAR depth as base64 float32 (AR-image space)
///     plus arIntrinsics/arImageSize/jpegToARTransform for sampling it.
- (NSDictionary * _Nullable)frameDataForId:(NSString *)frameId
                                   options:(NSDictionary * _Nullable)options;

#pragma mark - Session Management

/// Increment session ID (call on AR session reset/relocalization)
- (void)handleSessionReset;

@end

NS_ASSUME_NONNULL_END
