//
//  VRTARSceneNavigator.h
//  ViroReact
//
//  Created by Andy Chu on 6/12/17.
//  Copyright © 2017 Viro Media. All rights reserved.
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
//

#import <Foundation/Foundation.h>
#import <React/RCTBridge.h>
#import <React/RCTInvalidating.h>
#import "VRTNode.h"

@class VRTScene;
@class VROFrameCaptureService;

@interface VRTARSceneNavigator : VRTView<VRORenderDelegate, RCTInvalidating>

@property (nonatomic, assign) NSInteger currentSceneIndex;
@property (nonatomic, readwrite, strong) NSMutableArray<VRTScene *> *currentViews;
@property (readwrite, nonatomic) VRTScene *currentScene;
@property (nonatomic, copy) NSString *worldAlignment;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onExitViro;
@property (nonatomic, assign) BOOL autofocus;
@property (nonatomic, copy) NSString *videoQuality;
@property (nonatomic, assign) NSInteger numberOfTrackedImages;
@property (nonatomic, readwrite) BOOL hdrEnabled;
@property (nonatomic, readwrite) BOOL pbrEnabled;
@property (nonatomic, readwrite) BOOL bloomEnabled;
@property (nonatomic, readwrite) BOOL shadowsEnabled;
@property (nonatomic, readwrite) BOOL multisamplingEnabled;
@property (nonatomic, copy) NSString *occlusionMode;
@property (nonatomic, assign) BOOL depthEnabled;
@property (nonatomic, assign) BOOL depthDebugEnabled;
@property (nonatomic, copy, nullable) NSDictionary *scanWaveConfig;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onScanWaveComplete;
@property (nonatomic, assign) BOOL semanticDebugEnabled;
@property (nonatomic, assign) float monocularDepthScale;
@property (nonatomic, assign) int monocularDepthTargetFPS;
@property (nonatomic, assign) BOOL frontCameraEnabled;
@property (nonatomic, assign) float semanticConfidenceThreshold;
@property (nonatomic, copy) NSString *cloudAnchorProvider;
@property (nonatomic, copy) NSString *geospatialAnchorProvider;

// On-demand monocular depth for detection resolution (fork >= 2.61.72).
// When YES the session preloads the bundled depth model (without per-frame
// estimation) and resolveDetections gains a "mono" rung below real plane
// geometry: the model runs once on the captured frame's own JPEG the first
// time a point needs it. Meant for devices without LiDAR; on LiDAR devices
// the lidar rung answers first and this is never reached.
@property (nonatomic, assign) BOOL monoDepthResolveEnabled;
// With monoDepthResolveEnabled: run the depth model on a square crop around
// each detection's box (points carry "box") rather than the whole frame.
// Default NO — adopt after the tape test says the crop does not hurt.
@property (nonatomic, assign) BOOL monoDepthCropEnabled;

// World mesh properties
@property (nonatomic, assign) BOOL worldMeshEnabled;
@property (nonatomic, copy, nullable) NSDictionary *worldMeshConfig;
@property (nonatomic, copy, nullable) RCTDirectEventBlock onWorldMeshUpdated;

// World map persistence - now uses imperative ref-based API (properties removed)
// Callback fired when world mapping status changes (for UI feedback)
@property (nonatomic, copy, nullable) RCTDirectEventBlock onWorldMappingStatusChanged;

- (instancetype)initWithBridge:(RCTBridge *)bridge;
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)removeReactSubview:(UIView *)subview;
- (NSArray *)reactSubviews;
- (UIView *)reactSuperview;
- (UIView *)rootVROView;
- (void)invalidate;
- (void)cleanupViroResources;
- (VROVector3f)unprojectPoint:(VROVector3f)point;
- (VROVector3f)projectPoint:(VROVector3f)point;

// Native ARSession access for advanced features like ARWorldMap
- (ARSession *)getNativeARSession;

#pragma mark - World Map Persistence Methods (Imperative API)

// Completion handler for world map operations - includes error code for structured handling
// filePath is provided on successful save operations (nil for load/delete or on error)
typedef void (^WorldMapCompletionHandler)(BOOL success,
                                           NSString * _Nullable errorCode,
                                           NSString * _Nullable errorMessage,
                                           NSString * _Nullable filePath);

/**
 * Save the current world map to persistent storage.
 *
 * @param sessionId Unique identifier for the session (used for filename if filePath is nil)
 * @param filePath Optional custom path to save the world map. If nil, saves to default cache location.
 * @param completionHandler Called with success/errorCode/errorMessage/filePath
 *
 * Error codes:
 * - BUSY: Another world map operation is in progress
 * - SESSION_UNAVAILABLE: AR session not available
 * - WORLD_MAP_NOT_READY: Tracking state not normal or mapping status not mapped/extending
 */
- (void)saveWorldMapForSession:(NSString *)sessionId
                      filePath:(NSString * _Nullable)filePath
             completionHandler:(WorldMapCompletionHandler)completionHandler;

/**
 * Load a previously saved world map and restart the AR session.
 *
 * @param sessionId Unique identifier for the session to load
 * @param filePath Optional custom path to load from. If nil, loads from default cache location.
 * @param completionHandler Called with success/errorCode/errorMessage
 *
 * Note: success=YES means the session was restarted with initialWorldMap set.
 * Relocalization happens asynchronously - monitor trackingState for .normal.
 *
 * Error codes:
 * - BUSY: Another world map operation is in progress
 * - NOT_FOUND: No saved world map file found for this sessionId
 * - DECODE_FAILED: Failed to decode the world map file
 * - SESSION_UNAVAILABLE: AR session not available
 */
- (void)loadWorldMapForSession:(NSString *)sessionId
                      filePath:(NSString * _Nullable)filePath
             completionHandler:(WorldMapCompletionHandler)completionHandler;

/**
 * Delete a previously saved world map from storage.
 *
 * @param sessionId Unique identifier for the session to delete
 * @param completionHandler Called with success/errorCode/errorMessage
 *
 * Error codes:
 * - BUSY: Another world map operation is in progress
 * - NOT_FOUND: No saved world map file found for this sessionId
 */
- (void)deleteWorldMapForSession:(NSString *)sessionId
               completionHandler:(WorldMapCompletionHandler)completionHandler;

/**
 * Get current world mapping status for UI feedback.
 *
 * @param completionHandler Called with status dictionary containing:
 *   - mappingStatus: "notAvailable" | "limited" | "extending" | "mapped"
 *   - trackingState: "notAvailable" | "limited" | "normal"
 *   - canSave: BOOL (true if ready to save world map)
 */
- (void)getWorldMappingStatusWithCompletionHandler:(void (^)(NSDictionary *result))completionHandler;

#pragma mark - Scan Wave Methods (Imperative API)

typedef void (^ScanWaveCompletionHandler)(BOOL success, NSString * _Nullable error);

/**
 * Trigger a scan wave effect with optional config overrides and looping.
 * Config supports all visual parameters plus:
 *   - repeatCount (int): Number of sweep loops. Default: 1
 *   - totalDuration (float, ms): Max total animation time. Default: 0 (use repeatCount)
 */
- (void)triggerScanWave:(NSDictionary * _Nullable)config
      completionHandler:(ScanWaveCompletionHandler)completionHandler;

/**
 * Stop the scan wave effect immediately.
 */
- (void)stopScanWave;

#pragma mark - World Mesh Snapshot (Imperative API)

/**
 * Get a snapshot of the current world mesh from ARKit.
 * Options:
 *   - includeGeometry (BOOL): If YES, includes base64-encoded vertex/index/normal/classification data
 *
 * @param options Optional configuration dictionary
 * @param completionHandler Called with result dictionary containing success, stats, and optionally anchors
 */
- (void)getWorldMeshSnapshotWithOptions:(NSDictionary * _Nullable)options
                      completionHandler:(void (^)(NSDictionary *result))completionHandler;

#pragma mark - Media Capture Methods

- (void)startVideoRecording:(NSString *)fileName
           saveToCameraRoll:(BOOL)saveToCameraRoll
                    onError:(RCTResponseSenderBlock)onError;

- (void)stopVideoRecordingWithHandler:(VROViewWriteMediaFinishBlock)completionHandler;

- (void)takeScreenshot:(NSString *)fileName
      saveToCameraRoll:(BOOL)saveToCameraRoll
     completionHandler:(VROViewWriteMediaFinishBlock)completionHandler;

- (void)takeHighResolutionPhoto:(NSString *)fileName
               saveToCameraRoll:(BOOL)saveToCameraRoll
              completionHandler:(VROViewWriteMediaFinishBlock)completionHandler;

// View transform zoom - scales the entire ARView using CGAffineTransform
- (void)setViewZoom:(float)zoomFactor;

// Render zoom (projection-based) - modifies projection matrix and camera texture
// This zoom is captured in screenshots, video recordings, and high-res photos
- (void)setRenderZoom:(float)zoomFactor;
- (float)getRenderZoom;
- (float)getMaxRenderZoom;
- (void)setMaxRenderZoom:(float)maxZoom;

#pragma mark - Cloud Anchor Methods

// Cloud Anchor completion handler types
// Host callback now includes anchor's world-space position and rotation for relocalization
typedef void (^CloudAnchorHostCompletionHandler)(BOOL success,
                                                  NSString * _Nullable cloudAnchorId,
                                                  NSArray<NSNumber *> * _Nullable position,   // [x, y, z]
                                                  NSArray<NSNumber *> * _Nullable rotation,   // [rx, ry, rz] degrees
                                                  NSString * _Nullable error,
                                                  NSString * _Nonnull state);

typedef void (^CloudAnchorResolveCompletionHandler)(BOOL success,
                                                     NSDictionary * _Nullable anchorData,
                                                     NSString * _Nullable error,
                                                     NSString * _Nonnull state);

- (void)hostCloudAnchor:(NSString *)anchorId
                ttlDays:(NSInteger)ttlDays
      completionHandler:(CloudAnchorHostCompletionHandler)completionHandler;

- (void)resolveCloudAnchor:(NSString *)cloudAnchorId
         completionHandler:(CloudAnchorResolveCompletionHandler)completionHandler;

- (void)cancelCloudAnchorOperations;

#pragma mark - Manual Anchor Creation Methods

// Add anchor completion handler type - includes pose data (position + camera rotation quaternion)
typedef void (^AddAnchorCompletionHandler)(BOOL success,
                                           NSString * _Nullable anchorId,
                                           NSArray<NSNumber *> * _Nullable position,
                                           NSArray<NSNumber *> * _Nullable cameraRotation,  // camera quaternion [x,y,z,w]
                                           NSString * _Nullable error);

/**
 * Create an AR anchor at the specified world position.
 *
 * @param position Array of 3 floats [x, y, z] specifying world position
 * @param completionHandler Called with success/anchorId/error
 */
- (void)addAnchorAtPosition:(NSArray<NSNumber *> *)position
          completionHandler:(AddAnchorCompletionHandler)completionHandler;

/**
 * Create a native ARKit anchor at the specified world position and immediately host it to the cloud.
 * This is an atomic operation that avoids the lookup issue when hosting manually-created anchors.
 *
 * @param position Array of 3 floats [x, y, z] specifying world position
 * @param ttlDays Time-to-live in days for the cloud anchor (1-365)
 * @param completionHandler Called with success/cloudAnchorId/error/state
 */
- (void)createAndHostCloudAnchorAtPosition:(NSArray<NSNumber *> *)position
                                   ttlDays:(NSInteger)ttlDays
                         completionHandler:(CloudAnchorHostCompletionHandler)completionHandler;

#pragma mark - AR Session Recording Methods

// Records the AR session (video + IMU + tracked pose) to local storage — see
// ViroWorkspace/plans/viro-ar-recording-playback-plan.md. Not to be confused
// with startVideoRecording/stopVideoRecording, which capture the rendered
// screen only.
typedef void (^RecordingStartCompletionHandler)(BOOL success,
                                                 NSString * _Nullable error);

// recordVideo:NO = pose-only mode — session.jsonl without video.mp4, for a
// caller whose video already comes from the rendered-take recorder.
- (void)startRecording:(NSString *)outputDir
            recordVideo:(BOOL)recordVideo
      completionHandler:(RecordingStartCompletionHandler)completionHandler;

- (void)stopRecording;

// One of "None", "Recording", "IOError", "Unsupported" — mirrors
// VROARRecordingStatus (VROARSession.h).
- (NSString *)getRecordingStatus;

#pragma mark - Geospatial API Methods

// Geospatial completion handler types
typedef void (^GeospatialPoseCompletionHandler)(BOOL success,
                                                  NSDictionary * _Nullable poseData,
                                                  NSString * _Nullable error);

typedef void (^VPSAvailabilityCompletionHandler)(NSString * _Nonnull availability);

typedef void (^GeospatialAnchorCompletionHandler)(BOOL success,
                                                    NSDictionary * _Nullable anchorData,
                                                    NSString * _Nullable error);

// Geospatial mode
- (BOOL)isGeospatialModeSupported;
- (BOOL)isLocationAccuracyReduced;
- (void)setGeospatialModeEnabled:(BOOL)enabled;

// Earth tracking state
- (NSString *)getEarthTrackingState;

// Camera geospatial pose
- (void)getCameraGeospatialPose:(GeospatialPoseCompletionHandler)completionHandler;

// VPS availability
- (void)checkVPSAvailability:(double)latitude
                   longitude:(double)longitude
           completionHandler:(VPSAvailabilityCompletionHandler)completionHandler;

// Geospatial anchors
// Note: quaternion accepts both array [x, y, z, w] and dictionary {x, y, z, w}
- (void)createGeospatialAnchor:(double)latitude
                     longitude:(double)longitude
                      altitude:(double)altitude
                    quaternion:(id)quaternion
             completionHandler:(GeospatialAnchorCompletionHandler)completionHandler;

- (void)createTerrainAnchor:(double)latitude
                  longitude:(double)longitude
        altitudeAboveTerrain:(double)altitudeAboveTerrain
                  quaternion:(id)quaternion
           completionHandler:(GeospatialAnchorCompletionHandler)completionHandler;

- (void)createRooftopAnchor:(double)latitude
                  longitude:(double)longitude
       altitudeAboveRooftop:(double)altitudeAboveRooftop
                  quaternion:(id)quaternion
           completionHandler:(GeospatialAnchorCompletionHandler)completionHandler;

- (void)removeGeospatialAnchor:(NSString *)anchorId;

// ReactVision-specific: save GPS anchor to backend (returns platform UUID), no local AR anchor
- (void)hostGeospatialAnchor:(double)latitude
                   longitude:(double)longitude
                    altitude:(double)altitude
               altitudeMode:(NSString *)altitudeMode
           completionHandler:(void (^)(BOOL success, NSString * _Nullable platformUuid, NSString * _Nullable error))completionHandler;

// ReactVision-specific: fetch GPS coords from backend by UUID + create local AR anchor
- (void)resolveGeospatialAnchor:(NSString *)platformUuid
                      quaternion:(id)quaternion
              completionHandler:(GeospatialAnchorCompletionHandler)completionHandler;

// ReactVision Geospatial CRUD
- (void)rvGetGeospatialAnchor:(NSString *)anchorId
            completionHandler:(void (^)(BOOL success, NSDictionary *anchorData, NSString *error))completionHandler;
- (void)rvFindNearbyGeospatialAnchors:(double)latitude
                            longitude:(double)longitude
                               radius:(double)radius
                                limit:(int)limit
                    completionHandler:(void (^)(BOOL success, NSArray *anchors, NSString *error))completionHandler;
- (void)rvUpdateGeospatialAnchor:(NSString *)anchorId
                    sceneAssetId:(NSString *)sceneAssetId
                         sceneId:(NSString *)sceneId
                            name:(NSString *)name
                     userAssetId:(NSString *)userAssetId
               completionHandler:(void (^)(BOOL success, NSDictionary *anchorData, NSString *error))completionHandler;
- (void)rvUploadAsset:(NSString *)filePath
            assetType:(NSString *)assetType
             fileName:(NSString *)fileName
           appUserId:(NSString *)appUserId
    completionHandler:(void (^)(BOOL success, NSString *userAssetId, NSString *fileUrl, NSString *error))completionHandler;
// WS-C: serialize the current world mesh to a temp file — pass the returned
// path straight into rvUploadAsset(). locationTransformCsv is the value
// finishScan()'s success callback returned (16 comma-separated floats);
// there is no placed anchor for a finishScan()-hosted mesh to read a
// transform from otherwise. Returns nil if there is no current mesh.
- (NSString *)rvSnapshotWorldMeshToFile:(NSString *)locationTransformCsv;
// WS-C: load a mesh snapshot (downloaded to filePath by the app from the
// resolved anchor's asset fileUrl) and attach it for both physics collision
// and visual occlusion. resolvedTransformCsv is the resolved anchor's
// transform (16 comma-separated floats). Requires worldMeshEnabled to be
// true. Returns NO if there is no AR scene, no world mesh, or the file is
// malformed.
- (BOOL)rvLoadWorldMeshFromFile:(NSString *)filePath
              resolvedTransform:(NSString *)resolvedTransformCsv;
- (void)rvDeleteGeospatialAnchor:(NSString *)anchorId
               completionHandler:(void (^)(BOOL success, NSString *error))completionHandler;
- (void)rvListGeospatialAnchors:(int)limit
                         offset:(int)offset
              completionHandler:(void (^)(BOOL success, NSArray *anchors, NSString *error))completionHandler;

// Cloud anchor management
- (void)rvStartScan;
- (void)rvFinishScan:(NSInteger)ttlDays
   completionHandler:(void (^)(BOOL success, NSString *cloudAnchorId,
                               NSString *locationTransformCsv, NSString *error))completionHandler;
- (void)rvGetCloudAnchor:(NSString *)anchorId
       completionHandler:(void (^)(BOOL success, NSDictionary *anchorData, NSString *error))completionHandler;
- (void)rvListCloudAnchors:(int)limit
                    offset:(int)offset
         completionHandler:(void (^)(BOOL success, NSArray *anchors, NSString *error))completionHandler;
- (void)rvUpdateCloudAnchor:(NSString *)anchorId
                       name:(NSString *)name
                description:(NSString *)description
                   isPublic:(BOOL)isPublic
          completionHandler:(void (^)(BOOL success, NSDictionary *anchorData, NSString *error))completionHandler;
- (void)rvDeleteCloudAnchor:(NSString *)anchorId
          completionHandler:(void (^)(BOOL success, NSString *error))completionHandler;
- (void)rvFindNearbyCloudAnchors:(double)latitude
                       longitude:(double)longitude
                          radius:(double)radius
                           limit:(int)limit
               completionHandler:(void (^)(BOOL success, NSArray *anchors, NSString *error))completionHandler;
- (void)rvGetProject:(void (^)(BOOL success, NSString *data, NSString *error))completionHandler;
- (void)rvGetScene:(NSString *)sceneId
 completionHandler:(void (^)(BOOL success, NSString *data, NSString *error))completionHandler;
- (void)rvGetSceneAssets:(NSString *)sceneId
      completionHandler:(void (^)(BOOL success, NSArray *assets, NSString *error))completionHandler;
- (void)rvAttachAssetToCloudAnchor:(NSString *)anchorId
                           fileUrl:(NSString *)fileUrl
                          fileSize:(int64_t)fileSize
                              name:(NSString *)name
                         assetType:(NSString *)assetType
                    externalUserId:(NSString *)externalUserId
                 completionHandler:(void (^)(BOOL success, NSString *error))completionHandler;
- (void)rvRemoveAssetFromCloudAnchor:(NSString *)anchorId
                             assetId:(NSString *)assetId
                   completionHandler:(void (^)(BOOL success, NSString *error))completionHandler;
- (void)rvTrackCloudAnchorResolution:(NSString *)anchorId
                             success:(BOOL)success
                          confidence:(double)confidence
                          matchCount:(int)matchCount
                         inlierCount:(int)inlierCount
                    processingTimeMs:(int)processingTimeMs
                            platform:(NSString *)platform
                      externalUserId:(NSString *)externalUserId
                   completionHandler:(void (^)(BOOL success, NSString *error))completionHandler;

#pragma mark - Scene Semantics API Methods

// Check if Scene Semantics mode is supported on this device
- (BOOL)isSemanticModeSupported;

// Enable or disable Scene Semantics mode
- (void)setSemanticModeEnabled:(BOOL)enabled;

// Get the fraction of pixels for each semantic label
// Returns a dictionary with label names (sky, building, etc.) as keys
- (NSDictionary *)getSemanticLabelFractions;

// Get the fraction of pixels for a specific semantic label
// @param label The semantic label name (e.g., "sky", "building", "road")
// @return The fraction of pixels (0.0-1.0)
- (float)getSemanticLabelFraction:(NSString *)label;

#pragma mark - Monocular Depth Estimation API Methods

// When enabled, monocular depth will be used even on devices with LiDAR
// This allows consistency across device types, testing, or depth beyond LiDAR's ~5m range
- (void)setPreferMonocularDepth:(BOOL)prefer;

// Check if monocular depth is preferred over LiDAR
- (BOOL)isPreferMonocularDepth;

#pragma mark - Frame Streaming API (for Gemini Vision integration)

// Frame streaming event callback
@property (nonatomic, copy, nullable) RCTDirectEventBlock onFrameUpdate;

// Frame capture service for streaming AR frames to JavaScript
@property (nonatomic, strong, nullable) VROFrameCaptureService *frameCaptureService;

// Start streaming AR frames with the given configuration
// Config keys: enabled (BOOL), width (int), height (int), fps (float),
// quality (float), includeImageData (BOOL, default YES; NO = metadata-only
// events, fetch bytes via getFrameData:), verbose (BOOL, default NO)
- (void)startFrameStream:(NSDictionary *)config;

// Stop streaming AR frames
- (void)stopFrameStream;

// Stop the frame pump timer (idempotent)
- (void)stopFrameStreamTimer;

// Cap the renderer's CADisplayLink rate (thermal control). 0 = display max
// (ProMotion: up to 120). The link lives inside ViroKit; this reaches it via
// KVC pinned to our own framework build.
- (void)setRenderFrameRate:(NSInteger)fps;

// On-demand image fetch for metadata-only streaming.
// Returns: {frameId, timestamp, sessionId, imageData (base64), width, height}
// or {frameId, error} if the frame was evicted from the ring buffer.
- (void)getFrameData:(NSString *)frameId
             options:(NSDictionary * _Nullable)options
   completionHandler:(void (^)(NSDictionary * _Nonnull result))completionHandler;

- (void)getFrameData:(NSString *)frameId
   completionHandler:(void (^)(NSDictionary * _Nonnull result))completionHandler;

// Encode the CURRENT camera frame now (bypasses the stream's rate limiter).
// Same result shape as getFrameData:, imageData included, or {frameId, error}.
- (void)captureFrameNow:(void (^)(NSDictionary * _Nonnull result))completionHandler;

// The navigator most recently created and not yet deallocated. Lets module
// methods whose work is thread-safe (ring reads, on-demand capture) answer
// without a UIManager round trip through the main thread.
+ (nullable instancetype)activeNavigator;

// Resolve 2D detection points to 3D world coordinates using capture-time data
// Points array: [{x: 0-1, y: 0-1}, ...]
// Returns: {frameId, results: [{input, ok, worldPos?, confidence?, method?, error?}]}
- (void)resolveDetections:(NSString *)frameId
                   points:(NSArray<NSDictionary *> *)points
        completionHandler:(void (^)(NSDictionary * _Nonnull result))completionHandler;

@end
