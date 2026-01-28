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
@property (nonatomic, assign) BOOL depthDebugEnabled;
@property (nonatomic, copy) NSString *cloudAnchorProvider;
@property (nonatomic, copy) NSString *geospatialAnchorProvider;

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

// Monocular depth download progress handler
typedef void (^MonocularDepthDownloadProgressHandler)(float progress);
typedef void (^MonocularDepthDownloadCompletionHandler)(BOOL success, NSString * _Nullable error);

// Check if monocular depth estimation is supported on this device (iOS 14.0+)
- (BOOL)isMonocularDepthSupported;

// Check if the monocular depth model has been downloaded
- (BOOL)isMonocularDepthModelDownloaded;

// Enable or disable monocular depth estimation for non-LiDAR devices
// Note: Model must be downloaded first using downloadMonocularDepthModel
- (void)setMonocularDepthEnabled:(BOOL)enabled;

// Set the base URL for downloading the depth model
// The full URL will be: baseURL/DepthPro.mlmodelc.zip
- (void)setMonocularDepthModelURL:(NSString *)baseURL;

// Download the monocular depth model if not already downloaded
- (void)downloadMonocularDepthModelWithProgress:(MonocularDepthDownloadProgressHandler)progressHandler
                              completionHandler:(MonocularDepthDownloadCompletionHandler)completionHandler;

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
// Config keys: enabled (BOOL), width (int), height (int), fps (float), quality (float)
- (void)startFrameStream:(NSDictionary *)config;

// Stop streaming AR frames
- (void)stopFrameStream;

// Resolve 2D detection points to 3D world coordinates using capture-time data
// Points array: [{x: 0-1, y: 0-1}, ...]
// Returns: {frameId, results: [{input, ok, worldPos?, confidence?, method?, error?}]}
- (void)resolveDetections:(NSString *)frameId
                   points:(NSArray<NSDictionary *> *)points
        completionHandler:(void (^)(NSDictionary * _Nonnull result))completionHandler;

@end
