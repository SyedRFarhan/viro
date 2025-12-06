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

- (instancetype)initWithBridge:(RCTBridge *)bridge;
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex;
- (void)removeReactSubview:(UIView *)subview;
- (NSArray *)reactSubviews;
- (UIView *)reactSuperview;
- (UIView *)rootVROView;
- (void)invalidate;
- (VROVector3f)unprojectPoint:(VROVector3f)point;
- (VROVector3f)projectPoint:(VROVector3f)point;

- (void)startVideoRecording:(NSString *)fileName
           saveToCameraRoll:(BOOL)saveToCameraRoll
                    onError:(RCTResponseSenderBlock)onError;

- (void)stopVideoRecordingWithHandler:(VROViewWriteMediaFinishBlock)completionHandler;

- (void)takeScreenshot:(NSString *)fileName
      saveToCameraRoll:(BOOL)saveToCameraRoll
     completionHandler:(VROViewWriteMediaFinishBlock)completionHandler;

#pragma mark - Cloud Anchor Methods

// Cloud Anchor completion handler types
typedef void (^CloudAnchorHostCompletionHandler)(BOOL success,
                                                  NSString * _Nullable cloudAnchorId,
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
- (void)createGeospatialAnchor:(double)latitude
                     longitude:(double)longitude
                      altitude:(double)altitude
                    quaternion:(NSArray *)quaternion
             completionHandler:(GeospatialAnchorCompletionHandler)completionHandler;

- (void)createTerrainAnchor:(double)latitude
                  longitude:(double)longitude
        altitudeAboveTerrain:(double)altitudeAboveTerrain
                  quaternion:(NSArray *)quaternion
           completionHandler:(GeospatialAnchorCompletionHandler)completionHandler;

- (void)createRooftopAnchor:(double)latitude
                  longitude:(double)longitude
       altitudeAboveRooftop:(double)altitudeAboveRooftop
                  quaternion:(NSArray *)quaternion
           completionHandler:(GeospatialAnchorCompletionHandler)completionHandler;

- (void)removeGeospatialAnchor:(NSString *)anchorId;

@end
