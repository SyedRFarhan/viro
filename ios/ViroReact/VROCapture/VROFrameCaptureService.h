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

#pragma mark - Session Management

/// Increment session ID (call on AR session reset/relocalization)
- (void)handleSessionReset;

@end

NS_ASSUME_NONNULL_END
