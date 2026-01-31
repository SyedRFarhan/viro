//
//  VRTARSceneNavigator.mm
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

#import <ARKit/ARKit.h>
#import <ViroKit/ViroKit.h>
#import <AVFoundation/AVFoundation.h>
#import "VRTARSceneNavigator.h"
#import <React/RCTAssert.h>
#import <React/RCTLog.h>
#import "VRTARScene.h"
#import "VRTNotifications.h"
#import <React/RCTRootView.h>
#import <React/RCTUtils.h>
#import "VRTPerfMonitor.h"
#import "VRTMaterialManager.h"
#import <ViroKit/VROGeospatialAnchor.h>
#import <ViroKit/VROSemantics.h>
#import <ViroKit/VROARScene.h>
#import <ViroKit/VROARWorldMesh.h>
#import <ViroKit/VROPlatformUtil.h>
#import "VROFrameCaptureService.h"
#import "VRODetectionResolver.h"
#import "VROFrameRingBuffer.h"

// World map operation state for concurrency guard
typedef NS_ENUM(NSInteger, VRTWorldMapOp) {
    VRTWorldMapOpNone = 0,
    VRTWorldMapOpSaving,
    VRTWorldMapOpLoading,
    VRTWorldMapOpDeleting
};

@implementation VRTARSceneNavigator {
    id <VROView> _vroView;
    NSInteger _currentStackPosition;
    RCTBridge *_bridge;
    VROVideoQuality _vroVideoQuality;
    BOOL _hasCleanedUp;
    EAGLContext *_eaglContext;

    // Pending configuration for features that may be set before session is ready
    BOOL _pendingSemanticModeEnabled;
    BOOL _needsSemanticModeApply;
    BOOL _pendingGeospatialModeEnabled;
    BOOL _needsGeospatialModeApply;

    // World mesh configuration
    BOOL _pendingWorldMeshEnabled;
    BOOL _needsWorldMeshApply;
    VROWorldMeshConfig _worldMeshConfigCpp;

    // World map persistence - imperative API with concurrency guard
    VRTWorldMapOp _worldMapOpInFlight;

    // World mapping status change detection
    ARWorldMappingStatus _lastWorldMappingStatus;
    ARTrackingState _lastTrackingState;
    BOOL _worldMappingStatusInitialized;

    // Frame streaming timer
    NSTimer *_frameStreamTimer;
}

- (instancetype)initWithBridge:(RCTBridge *)bridge {
    self = [super initWithBridge:bridge];
    if (self) {
        // Load materials; must be done each time we have a new context (e.g. after
        // the EGL context is created by the VROViewAR
        VRTMaterialManager *materialManager = [bridge materialManager];
        [materialManager reloadMaterials];
        
        [self setFrame:CGRectMake(0, 0,
                                  [[UIScreen mainScreen] bounds].size.width,
                                  [[UIScreen mainScreen] bounds].size.height)];
        self.currentViews = [[NSMutableArray alloc] init];
        _currentStackPosition = -1;

        _bridge = bridge;
        _autofocus = YES;
        _vroVideoQuality = VROVideoQuality::High;
        _numberOfTrackedImages = 0; // disable this
        _hdrEnabled = YES;
        _pbrEnabled = YES;
        _bloomEnabled = YES;
        _shadowsEnabled = YES;
        _multisamplingEnabled = NO;

        // World map persistence - imperative API
        _worldMapOpInFlight = VRTWorldMapOpNone;

        // World mapping status change detection - not initialized yet
        _worldMappingStatusInitialized = NO;
        _lastWorldMappingStatus = ARWorldMappingStatusNotAvailable;
        _lastTrackingState = ARTrackingStateNotAvailable;
    }
    return self;
}

// Custom setter for debugging - logs when the callback is assigned
- (void)setOnWorldMappingStatusChanged:(RCTDirectEventBlock)onWorldMappingStatusChanged {
    RCTLogInfo(@"[ViroAR] setOnWorldMappingStatusChanged called, callback is %s",
               onWorldMappingStatusChanged ? "SET" : "NIL");
    _onWorldMappingStatusChanged = [onWorldMappingStatusChanged copy];
}

- (void)setAutofocus:(BOOL)autofocus {
    _autofocus = autofocus;
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        arSession->setAutofocus(_autofocus);
    }
}

- (void)setVideoQuality:(NSString *)videoQuality {
    _videoQuality = videoQuality;
    if ([videoQuality caseInsensitiveCompare:@"Low"] == NSOrderedSame) {
        _vroVideoQuality = VROVideoQuality::Low;
    } else {
        _vroVideoQuality = VROVideoQuality::High;
    }
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        arSession->setVideoQuality(_vroVideoQuality);
    }
}

#pragma mark - View Transform Zoom

- (void)setViewZoom:(float)zoomFactor {
    NSLog(@"[ViroZoom] setViewZoom called with zoomFactor: %.2f", zoomFactor);
    // UIView transform zoom - scales the entire ARView visually
    // This is different from camera zoom - it's a visual scale of the rendered view
    if (_vroView) {
        // Cast to UIView to access view properties (VROView protocol is implemented by UIView subclasses)
        UIView *view = (UIView *)_vroView;

        // Set content mode to scale from center and clip overflow
        view.contentMode = UIViewContentModeCenter;
        view.clipsToBounds = YES;

        // Apply scale transform
        view.transform = CGAffineTransformMakeScale(zoomFactor, zoomFactor);
        NSLog(@"[ViroZoom] setViewZoom: SUCCESS - view transform set to %.2f (frame: %.0fx%.0f)",
              zoomFactor, view.frame.size.width, view.frame.size.height);
    } else {
        NSLog(@"[ViroZoom] setViewZoom: FAILED - vroView is nil");
    }
}

#pragma mark - Render Zoom (Projection-Based)

- (void)setRenderZoom:(float)zoomFactor {
    NSLog(@"[ViroZoom] setRenderZoom called with zoomFactor: %.2f", zoomFactor);
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            arSession->setRenderZoom(zoomFactor);
            NSLog(@"[ViroZoom] setRenderZoom: SUCCESS - render zoom set to %.2f", arSession->getRenderZoom());
        } else {
            NSLog(@"[ViroZoom] setRenderZoom: FAILED - arSession is nil");
        }
    } else {
        NSLog(@"[ViroZoom] setRenderZoom: FAILED - vroView is nil");
    }
}

- (float)getRenderZoom {
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            return arSession->getRenderZoom();
        }
    }
    return 1.0f;
}

- (float)getMaxRenderZoom {
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            return arSession->getMaxRenderZoom();
        }
    }
    return 5.0f;
}

- (void)setMaxRenderZoom:(float)maxZoom {
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            arSession->setMaxRenderZoom(maxZoom);
            NSLog(@"[ViroZoom] setMaxRenderZoom: SUCCESS - max render zoom set to %.2f", arSession->getMaxRenderZoom());
        }
    }
}

- (void)didSetProps:(NSArray<NSString *> *)changedProps {
    RCTLogInfo(@"[ViroAR] didSetProps called, _vroView=%s, _onWorldMappingStatusChanged=%s",
               _vroView ? "EXISTS" : "NIL",
               _onWorldMappingStatusChanged ? "SET" : "NIL");

    // if we haven't created the VROView, then create it now that
    // all the props have been set.
    if (!_vroView) {
        VROWorldAlignment worldAlignment = VROWorldAlignment::Gravity;
        if (_worldAlignment) {
            if ([_worldAlignment caseInsensitiveCompare:@"Gravity"] == NSOrderedSame) {
                worldAlignment = VROWorldAlignment::Gravity;
            } else if ([_worldAlignment caseInsensitiveCompare:@"GravityAndHeading"] == NSOrderedSame) {
                worldAlignment = VROWorldAlignment::GravityAndHeading;
            } else if ([_worldAlignment caseInsensitiveCompare:@"Camera"] == NSOrderedSame) {
                worldAlignment = VROWorldAlignment::Camera;
            }
        }
        
        _eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];

        VRORendererConfiguration config;
        config.enableHDR = _hdrEnabled;
        config.enablePBR = _pbrEnabled;
        config.enableBloom = _bloomEnabled;
        config.enableShadows = _shadowsEnabled;
        config.enableMultisampling = _multisamplingEnabled;
        
        _vroView = [[VROViewAR alloc] initWithFrame:CGRectMake(0, 0,
                                                               [[UIScreen mainScreen] bounds].size.width,
                                                               [[UIScreen mainScreen] bounds].size.height)
                                             config:config
                                            context:_eaglContext
                                     worldAlignment:worldAlignment];

        if (_currentScene != nil) {
            [_currentScene setView:_vroView];
        }

        VROViewAR *viewAR = (VROViewAR *) _vroView;
        [viewAR setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
        _vroView.renderDelegate = self;
        RCTLogInfo(@"[ViroAR] VROViewAR created, renderDelegate set to self, _onWorldMappingStatusChanged=%s",
                   _onWorldMappingStatusChanged ? "SET" : "NIL");

        [self addSubview:(UIView *)_vroView];

        [_bridge.perfMonitor setView:_vroView];

        // set the scene if it was set before this view was created (not likely)
        if (_currentScene) {
            [_vroView setSceneController:[_currentScene sceneController]];
        }

        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        arSession->setAutofocus(_autofocus);
        arSession->setVideoQuality(_vroVideoQuality);
        arSession->setNumberOfTrackedImages(_numberOfTrackedImages);

        // Apply initial occlusion mode if set
        if (_occlusionMode) {
            VROOcclusionMode mode = VROOcclusionMode::Disabled;
            if ([_occlusionMode caseInsensitiveCompare:@"depthBased"] == NSOrderedSame) {
                mode = VROOcclusionMode::DepthBased;
            } else if ([_occlusionMode caseInsensitiveCompare:@"peopleOnly"] == NSOrderedSame) {
                mode = VROOcclusionMode::PeopleOnly;
            }
            arSession->setOcclusionMode(mode);
        }

        // Apply initial depth debug setting if set
        if (_depthDebugEnabled) {
            [viewAR setDepthDebugEnabled:_depthDebugEnabled opacity:0.7f];
        }

        // Apply initial scan wave config and enabled state if set before view was ready
        if (_scanWaveConfig) {
            [viewAR setScanWaveConfig:_scanWaveConfig];
        }
        if (_scanWaveEnabled) {
            [viewAR setScanWaveEnabled:_scanWaveEnabled];
        }

        // Apply cloud anchor provider if it was set before view was ready
        if (_cloudAnchorProvider) {
            [self setCloudAnchorProvider:_cloudAnchorProvider];
        }

        // Apply geospatial anchor provider if it was set before view was ready
        if (_geospatialAnchorProvider) {
            [self setGeospatialAnchorProvider:_geospatialAnchorProvider];
        }

        // Apply pending semantic mode if set before view was ready
        if (_needsSemanticModeApply) {
            [self applySemanticModeEnabled];
            _needsSemanticModeApply = NO;
        }

        // Apply pending geospatial mode if set before view was ready
        if (_needsGeospatialModeApply) {
            [self applyGeospatialModeEnabled];
            _needsGeospatialModeApply = NO;
        }

        // World map persistence is now fully imperative via ref API
    }
}

- (UIView *)rootVROView {
    return (UIView *)_vroView;
}

//VROComponent overrides...
- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex {
    RCTAssert([subview isKindOfClass:[VRTARScene class]], @"VRTARNavigator only accepts VRTARScene subviews");
    [super insertReactSubview:subview atIndex:atIndex];
    
    VRTARScene *sceneView = (VRTARScene *)subview;
    
    [sceneView setView:_vroView];
    [self.currentViews insertObject:sceneView atIndex:atIndex];
    
    if (self.currentSceneIndex == atIndex){
        [self setSceneView:sceneView];
    }
}

-(void)setCurrentSceneIndex:(NSInteger)index {
    int currentViewsLength = (int)[_currentViews count];
    _currentSceneIndex = index;
    
    if (_currentSceneIndex < 0 || _currentSceneIndex > (currentViewsLength - 1)){
        // setCurrentSceneTag may be set before insertReactSubView class.
        // In this case, just return.
        return;
    }

    VRTScene *sceneView = [_currentViews objectAtIndex:index];
    [self setSceneView:sceneView];
}

- (void)removeReactSubview:(UIView *)subview {
    VRTARScene *sceneView = (VRTARScene *)subview;
    [self.currentViews removeObject:sceneView];
    [super removeReactSubview:subview];
}

- (NSArray *)reactSubviews {
    return self.currentViews;
}

- (UIView *)reactSuperview {
    return nil;
}

#pragma mark - VRORenderDelegate methods

- (void)setupRendererWithDriver:(std::shared_ptr<VRODriver>)driver {
    
}

- (void)startVideoRecording:(NSString *)fileName
           saveToCameraRoll:(BOOL)saveToCameraRoll
                    onError:(RCTResponseSenderBlock)onError {
    VROViewAR *viewAR = (VROViewAR *) _vroView;
    [viewAR startVideoRecording:fileName saveToCameraRoll:saveToCameraRoll errorBlock:^(NSInteger errorCode) {
        onError(@[@(errorCode)]);
    }];
}

- (void)stopVideoRecordingWithHandler:(VROViewWriteMediaFinishBlock)completionHandler {
    VROViewAR *viewAR = (VROViewAR *) _vroView;
    [viewAR stopVideoRecordingWithHandler:completionHandler];
}

- (void)takeScreenshot:(NSString *)fileName
      saveToCameraRoll:(BOOL)saveToCameraRoll
     completionHandler:(VROViewWriteMediaFinishBlock)completionHandler {
    VROViewAR *viewAR = (VROViewAR *) _vroView;
    [viewAR takeScreenshot:fileName saveToCameraRoll:saveToCameraRoll withCompletionHandler:completionHandler];

}

- (void)takeHighResolutionPhoto:(NSString *)fileName
               saveToCameraRoll:(BOOL)saveToCameraRoll
              completionHandler:(VROViewWriteMediaFinishBlock)completionHandler {
    VROViewAR *viewAR = (VROViewAR *) _vroView;
    [viewAR takeHighResolutionPhoto:fileName saveToCameraRoll:saveToCameraRoll withCompletionHandler:completionHandler];
}

- (void)setSceneView:(VRTScene *)sceneView {
    if (_currentScene == sceneView) {
        return;
    }

    if (_vroView) {
        if (_currentScene == nil) {
            [_vroView setSceneController:[sceneView sceneController]];
        } else {
            [_vroView setSceneController:[sceneView sceneController] duration:1 timingFunction:VROTimingFunctionType::EaseIn];
        }
    }

    _currentScene = sceneView;

    // Apply pending world mesh configuration if set before scene was ready
    if (_needsWorldMeshApply) {
        [self applyWorldMeshEnabled];
    }
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    // If newSuperview is nil, the view is being removed
    if (newSuperview == nil) {
        [self cleanupViroResources];
        
        // Critical: Clear pointer interactions to prevent crashes
        @try {
            self.interactions = @[];
        } @catch (NSException *exception) {
            NSLog(@"Error clearing interactions: %@", exception.reason);
        }
    }
    [super willMoveToSuperview:newSuperview];
}

- (void)cleanupViroResources {
    // Only cleanup once per instance
    if (_hasCleanedUp) {
        return;
    }
    _hasCleanedUp = YES;

    // Stop world map auto-save timer
    [self parentDidDisappear];

    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *)_vroView;

        // First pause the AR session
        [viewAR setPaused:YES];

        // Terminate AR session explicitly - synchronous cleanup for Fabric
        @try {
            std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
            if (arSession) {
                arSession->pause();

                // Synchronous cleanup to prevent race conditions in Fabric
                @try {
                    [viewAR deleteGL];
                } @catch (NSException *exception) {
                    NSLog(@"Error during AR view cleanup: %@", exception.reason);
                }
            } else {
                [viewAR deleteGL];
            }
        } @catch (NSException *exception) {
            NSLog(@"Error terminating AR session: %@", exception.reason);
            // Still try to delete GL resources
            @try {
                [viewAR deleteGL];
            } @catch (NSException *innerException) {
                NSLog(@"Error during AR view cleanup: %@", innerException.reason);
            }
        }

        // Remove the view from hierarchy before clearing reference
        [(UIView *)_vroView removeFromSuperview];

        // Clear the view reference to prevent dangling pointer
        _vroView = nil;
    }

    // Destroy the EAGLContext to release GPU resources
    // This must happen after deleteGL since GL operations require a valid context
    if (_eaglContext) {
        // Clear the current context if it's ours
        if ([EAGLContext currentContext] == _eaglContext) {
            [EAGLContext setCurrentContext:nil];
        }
        _eaglContext = nil;
    }
}

- (void)removeFromSuperview{
    // Fabric may call removeFromSuperview after willMoveToSuperview
    // So we need to handle cleanup in both places
    [self cleanupViroResources];
    
    // Clear any remaining pointer interactions before calling super
    @try {
        self.interactions = @[];
        
        // Also clear any gesture recognizers that might cause issues
        for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
            [self removeGestureRecognizer:gesture];
        }
    } @catch (NSException *exception) {
        NSLog(@"Error clearing interactions/gestures: %@", exception.reason);
    }
    
    [super removeFromSuperview];
}

- (void)dealloc {
    // Final safety net for cleanup
    [self cleanupViroResources];
}

#pragma mark - Fabric Compatibility

- (void)prepareForRecycle {
    // Called by Fabric architecture before reusing the view
    // We must clean up all resources here to prevent memory leaks
    [self cleanupViroResources];

    // Reset state flags for potential reuse
    _hasCleanedUp = NO;

    [super prepareForRecycle];
}

- (void)setNumberOfTrackedImages:(NSInteger)numberOfTrackedImages {
    _numberOfTrackedImages = numberOfTrackedImages;
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        arSession->setNumberOfTrackedImages(numberOfTrackedImages);
    }
}

- (void)setHdrEnabled:(BOOL)hdrEnabled {
    _hdrEnabled = hdrEnabled;
    if (_vroView) {
        [_vroView setHDREnabled:hdrEnabled];
    }
}

- (void)setPbrEnabled:(BOOL)pbrEnabled {
    _pbrEnabled = pbrEnabled;
    if (_vroView) {
        [_vroView setPBREnabled:pbrEnabled];
    }
}

- (void)setBloomEnabled:(BOOL)bloomEnabled {
    _bloomEnabled = bloomEnabled;
    if (_vroView) {
        [_vroView setBloomEnabled:bloomEnabled];
    }
}

- (void)setShadowsEnabled:(BOOL)shadowsEnabled {
    _shadowsEnabled = shadowsEnabled;
    if (_vroView) {
        [_vroView setShadowsEnabled:shadowsEnabled];
    }
}

- (void)setMultisamplingEnabled:(BOOL)multisamplingEnabled {
    _multisamplingEnabled = multisamplingEnabled;
}

- (void)setOcclusionMode:(NSString *)occlusionMode {
    _occlusionMode = occlusionMode;
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            VROOcclusionMode mode = VROOcclusionMode::Disabled;
            if ([occlusionMode caseInsensitiveCompare:@"depthBased"] == NSOrderedSame) {
                mode = VROOcclusionMode::DepthBased;
            } else if ([occlusionMode caseInsensitiveCompare:@"peopleOnly"] == NSOrderedSame) {
                mode = VROOcclusionMode::PeopleOnly;
            }
            arSession->setOcclusionMode(mode);
        }
    }
}

- (void)setDepthDebugEnabled:(BOOL)depthDebugEnabled {
    _depthDebugEnabled = depthDebugEnabled;
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        [viewAR setDepthDebugEnabled:depthDebugEnabled opacity:0.7f];
    }
}

- (void)setScanWaveEnabled:(BOOL)scanWaveEnabled {
    _scanWaveEnabled = scanWaveEnabled;
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        [viewAR setScanWaveEnabled:scanWaveEnabled];
    }
}

- (void)setScanWaveConfig:(NSDictionary *)scanWaveConfig {
    _scanWaveConfig = scanWaveConfig;
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        [viewAR setScanWaveConfig:scanWaveConfig];
    }
}

/*
 Unproject the given screen coordinates into world coordinates. The given screen coordinate vector must
 contain a Z element in the range [0,1], where 0 is the near clipping plane and 1 the far clipping plane.
 */
-(VROVector3f) unprojectPoint:(VROVector3f)point {
    if(_vroView == nil || _vroView.renderer == nil) {
        RCTLogError(@"Unable to unproject. Renderer not intialized");
    }
    
    VROVector3f unprojectedPoint = [_vroView unprojectPoint:point];
    return unprojectedPoint;
}

// Project the given world coordinates into screen coordinates.
-(VROVector3f) projectPoint:(VROVector3f)point {
    if(_vroView == nil || _vroView.renderer == nil) {
        RCTLogError(@"Unable to unproject. Renderer not intialized");
    }
    
    VROVector3f projectedPoint = [_vroView projectPoint:point];
    return projectedPoint;
}

#pragma mark - Native ARSession Access

- (ARSession *)getNativeARSession {
    if (!_vroView) {
        return nil;
    }
    VROViewAR *viewAR = (VROViewAR *) _vroView;
    return [viewAR getNativeARSession];
}

#pragma mark - Cloud Anchor Methods

- (void)setCloudAnchorProvider:(NSString *)cloudAnchorProvider {
    _cloudAnchorProvider = cloudAnchorProvider;

    RCTLogInfo(@"[ViroAR] Setting cloud anchor provider: %@", cloudAnchorProvider ?: @"none");

    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            if ([cloudAnchorProvider caseInsensitiveCompare:@"arcore"] == NSOrderedSame) {
                arSession->setCloudAnchorProvider(VROCloudAnchorProvider::ARCore);
                RCTLogInfo(@"[ViroAR] ARCore Cloud Anchors provider enabled");

                // Check if API key is configured
                NSString *apiKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GARAPIKey"];
                if (apiKey && apiKey.length > 0) {
                    RCTLogInfo(@"[ViroAR] GARAPIKey found in Info.plist (length: %lu)", (unsigned long)apiKey.length);
                } else {
                    RCTLogWarn(@"[ViroAR] WARNING: GARAPIKey not found in Info.plist. Cloud anchors will not work!");
                }
            } else {
                arSession->setCloudAnchorProvider(VROCloudAnchorProvider::None);
                RCTLogInfo(@"[ViroAR] Cloud Anchors disabled");
            }
        } else {
            RCTLogWarn(@"[ViroAR] AR session not available, cannot set cloud anchor provider");
        }
    } else {
        RCTLogInfo(@"[ViroAR] VROView not ready yet, cloud anchor provider will be set later");
    }
}

- (void)hostCloudAnchor:(NSString *)anchorId
                ttlDays:(NSInteger)ttlDays
      completionHandler:(CloudAnchorHostCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"AR view not initialized", @"ErrorInternal");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"AR session not available", @"ErrorInternal");
        }
        return;
    }

    // Find the anchor by ID in frame anchors
    std::string anchorIdStr = std::string([anchorId UTF8String]);
    std::shared_ptr<VROARAnchor> anchor = nullptr;

    std::unique_ptr<VROARFrame> &frame = arSession->getLastFrame();
    if (frame) {
        const std::vector<std::shared_ptr<VROARAnchor>> &anchors = frame->getAnchors();
        for (const auto &a : anchors) {
            if (a->getId() == anchorIdStr) {
                anchor = a;
                break;
            }
        }
    }

    if (!anchor) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"Anchor not found in session", @"ErrorCloudIdNotFound");
        }
        return;
    }

    // Host the anchor with TTL
    arSession->hostCloudAnchor(anchor,
        (int)ttlDays,
        [completionHandler](std::shared_ptr<VROARAnchor> hostedAnchor) {
            // Success callback - extract anchor's world-space position and rotation
            if (completionHandler) {
                NSString *cloudId = [NSString stringWithUTF8String:hostedAnchor->getCloudAnchorId().c_str()];

                // Extract position and rotation from anchor transform
                VROMatrix4f transform = hostedAnchor->getTransform();
                VROVector3f position = transform.extractTranslation();
                VROVector3f scale = transform.extractScale();
                VROVector3f rotation = transform.extractRotation(scale).toEuler();

                NSArray<NSNumber *> *posArray = @[@(position.x), @(position.y), @(position.z)];
                NSArray<NSNumber *> *rotArray = @[@(toDegrees(rotation.x)),
                                                   @(toDegrees(rotation.y)),
                                                   @(toDegrees(rotation.z))];

                completionHandler(YES, cloudId, posArray, rotArray, nil, @"Success");
            }
        },
        [completionHandler](std::string error) {
            // Failure callback
            if (completionHandler) {
                NSString *errorStr = [NSString stringWithUTF8String:error.c_str()];
                completionHandler(NO, nil, nil, nil, errorStr, @"ErrorInternal");
            }
        }
    );
}

- (void)resolveCloudAnchor:(NSString *)cloudAnchorId
         completionHandler:(CloudAnchorResolveCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR view not initialized", @"ErrorInternal");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR session not available", @"ErrorInternal");
        }
        return;
    }

    std::string cloudIdStr = std::string([cloudAnchorId UTF8String]);

    // Resolve the anchor
    arSession->resolveCloudAnchor(cloudIdStr,
        [completionHandler](std::shared_ptr<VROARAnchor> resolvedAnchor) {
            // Success callback - convert anchor to dictionary
            if (completionHandler) {
                VROMatrix4f transform = resolvedAnchor->getTransform();
                VROVector3f position = transform.extractTranslation();
                VROVector3f scale = transform.extractScale();
                VROVector3f rotation = transform.extractRotation(scale).toEuler();

                NSDictionary *anchorData = @{
                    @"anchorId": [NSString stringWithUTF8String:resolvedAnchor->getId().c_str()],
                    @"cloudAnchorId": [NSString stringWithUTF8String:resolvedAnchor->getCloudAnchorId().c_str()],
                    @"state": @"Success",
                    @"position": @[@(position.x), @(position.y), @(position.z)],
                    @"rotation": @[@(toDegrees(rotation.x)), @(toDegrees(rotation.y)), @(toDegrees(rotation.z))],
                    @"scale": @[@(scale.x), @(scale.y), @(scale.z)]
                };
                completionHandler(YES, anchorData, nil, @"Success");
            }
        },
        [completionHandler](std::string error) {
            // Failure callback
            if (completionHandler) {
                NSString *errorStr = [NSString stringWithUTF8String:error.c_str()];
                completionHandler(NO, nil, errorStr, @"ErrorInternal");
            }
        }
    );
}

- (void)cancelCloudAnchorOperations {
    // Currently a no-op - cloud operations are fire-and-forget
    // Future implementation could track and cancel pending operations
}

#pragma mark - Manual Anchor Creation Methods

- (void)addAnchorAtPosition:(NSArray<NSNumber *> *)position
          completionHandler:(AddAnchorCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"AR view not initialized");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"AR session not available");
        }
        return;
    }

    std::shared_ptr<VROARSessioniOS> arSessioniOS = std::dynamic_pointer_cast<VROARSessioniOS>(arSession);
    if (!arSessioniOS) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"Invalid AR session type");
        }
        return;
    }

    ARSession *nativeSession = arSessioniOS->getNativeARSession();
    if (!nativeSession) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"Native AR session not available");
        }
        return;
    }

    // Validate position array
    if (!position || position.count != 3) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"Position must be an array of 3 numbers [x, y, z]");
        }
        return;
    }

    // Extract position values
    float x = [[position objectAtIndex:0] floatValue];
    float y = [[position objectAtIndex:1] floatValue];
    float z = [[position objectAtIndex:2] floatValue];

    // Create native ARKit anchor with transform at the specified position
    simd_float4x4 transform = matrix_identity_float4x4;
    transform.columns[3] = simd_make_float4(x, y, z, 1.0);
    ARAnchor *nativeAnchor = [[ARAnchor alloc] initWithTransform:transform];
    NSString *anchorId = nativeAnchor.identifier.UUIDString;
    std::string anchorIdStr = std::string([anchorId UTF8String]);

    // Extract camera rotation as quaternion from current AR frame
    // This captures the user's viewing orientation at anchor creation time
    NSArray<NSNumber *> *cameraRotationArray = nil;
    ARFrame *currentFrame = nativeSession.currentFrame;
    if (currentFrame && currentFrame.camera) {
        simd_quatf cameraQuat = simd_quaternion(currentFrame.camera.transform);
        cameraRotationArray = @[
            @(cameraQuat.vector.x),
            @(cameraQuat.vector.y),
            @(cameraQuat.vector.z),
            @(cameraQuat.vector.w)
        ];
    }

    // Create VROARAnchor wrapper MANUALLY (bypasses buggy delegate path)
    // This pattern is from upstream createAnchoredNodeAtHitLocation()
    std::shared_ptr<VROARAnchor> viroAnchor = std::make_shared<VROARAnchor>();
    viroAnchor->setId(anchorIdStr);

    VROMatrix4f vTransform;
    vTransform.toIdentity();
    vTransform.translate(VROVector3f(x, y, z));
    viroAnchor->setTransform(vTransform);

    // Capture weak references for async blocks
    std::weak_ptr<VROARSessioniOS> session_w = arSessioniOS;
    std::weak_ptr<VROARAnchor> anchor_w = viroAnchor;

    // Add native anchor to ARKit on main thread, then register with Viro on renderer thread
    // This pre-registers the anchor before the delegate fires, preventing the null pointer crash
    dispatch_async(dispatch_get_main_queue(), ^{
        [nativeSession addAnchor:nativeAnchor];

        // Add VROARAnchor to Viro's tracking on renderer thread
        VROPlatformDispatchAsyncRenderer([session_w, anchor_w] {
            std::shared_ptr<VROARSessioniOS> session_s = session_w.lock();
            std::shared_ptr<VROARAnchor> anchor_s = anchor_w.lock();

            if (session_s && anchor_s) {
                session_s->addAnchor(anchor_s);
            }
        });
    });

    RCTLogInfo(@"[ViroAR] Created anchor at position [%.2f, %.2f, %.2f] with ID: %@", x, y, z, anchorId);

    if (completionHandler) {
        completionHandler(YES, anchorId, position, cameraRotationArray, nil);
    }
}

- (void)createAndHostCloudAnchorAtPosition:(NSArray<NSNumber *> *)position
                                   ttlDays:(NSInteger)ttlDays
                         completionHandler:(CloudAnchorHostCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"AR view not initialized", @"ErrorInternal");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    ARSession *nativeSession = [viewAR getNativeARSession];
    if (!nativeSession) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"ARKit session not available", @"ErrorInternal");
        }
        return;
    }

    std::shared_ptr<VROARSession> vroSession = [viewAR getARSession];
    if (!vroSession) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"VRO AR session not available", @"ErrorInternal");
        }
        return;
    }

    // Validate position
    if (!position || position.count != 3) {
        if (completionHandler) {
            completionHandler(NO, nil, nil, nil, @"Position must be an array of 3 numbers [x, y, z]", @"ErrorInternal");
        }
        return;
    }

    float x = [[position objectAtIndex:0] floatValue];
    float y = [[position objectAtIndex:1] floatValue];
    float z = [[position objectAtIndex:2] floatValue];

    // Create native ARKit anchor with transform
    simd_float4x4 transform = matrix_identity_float4x4;
    transform.columns[3] = simd_make_float4(x, y, z, 1.0);
    ARAnchor *nativeAnchor = [[ARAnchor alloc] initWithTransform:transform];

    // Add to ARKit session - this will trigger session:didAddAnchors: delegate
    // which creates the VROARAnchor wrapper and stores it in _nativeAnchorMap
    [nativeSession addAnchor:nativeAnchor];

    NSString *anchorId = nativeAnchor.identifier.UUIDString;
    RCTLogInfo(@"[ViroAR] Created native ARKit anchor at [%.2f, %.2f, %.2f] with ID: %@", x, y, z, anchorId);

    // Wait for ARKit to process the anchor into a frame (needs a few frame updates, ~150ms at 60fps)
    // before calling hostCloudAnchor which searches arFrame.anchors
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(150 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self hostCloudAnchor:anchorId ttlDays:ttlDays completionHandler:completionHandler];
    });
}

#pragma mark - Geospatial API Methods

- (void)setGeospatialAnchorProvider:(NSString *)geospatialAnchorProvider {
    _geospatialAnchorProvider = geospatialAnchorProvider;

    RCTLogInfo(@"[ViroAR] Setting geospatial anchor provider: %@", geospatialAnchorProvider ?: @"none");

    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            if ([geospatialAnchorProvider caseInsensitiveCompare:@"arcore"] == NSOrderedSame) {
                arSession->setGeospatialAnchorProvider(VROGeospatialAnchorProvider::ARCoreGeospatial);
                RCTLogInfo(@"[ViroAR] ARCore Geospatial provider enabled");

                // Check if API key is configured
                NSString *apiKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GARAPIKey"];
                if (apiKey && apiKey.length > 0) {
                    RCTLogInfo(@"[ViroAR] GARAPIKey found in Info.plist (length: %lu)", (unsigned long)apiKey.length);
                } else {
                    RCTLogWarn(@"[ViroAR] WARNING: GARAPIKey not found in Info.plist. Geospatial features will not work!");
                }
            } else {
                arSession->setGeospatialAnchorProvider(VROGeospatialAnchorProvider::None);
                RCTLogInfo(@"[ViroAR] Geospatial provider disabled");
            }
        } else {
            RCTLogWarn(@"[ViroAR] AR session not available, cannot set geospatial provider");
        }
    } else {
        RCTLogInfo(@"[ViroAR] VROView not ready yet, geospatial provider will be set later");
    }
}

- (BOOL)isGeospatialModeSupported {
    if (!_vroView) {
        return NO;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return NO;
    }

    return arSession->isGeospatialModeSupported();
}

- (void)setGeospatialModeEnabled:(BOOL)enabled {
    _pendingGeospatialModeEnabled = enabled;

    if (!_vroView) {
        _needsGeospatialModeApply = YES;
        RCTLogInfo(@"[ViroAR] Geospatial mode queued for later: %@", enabled ? @"enabled" : @"disabled");
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        _needsGeospatialModeApply = YES;
        RCTLogInfo(@"[ViroAR] Geospatial mode queued for later: %@", enabled ? @"enabled" : @"disabled");
        return;
    }

    [self applyGeospatialModeEnabled];
}

- (void)applyGeospatialModeEnabled {
    if (!_vroView) {
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return;
    }

    arSession->setGeospatialModeEnabled(_pendingGeospatialModeEnabled);
    _needsGeospatialModeApply = NO;
    RCTLogInfo(@"[ViroAR] Geospatial mode applied: %@", _pendingGeospatialModeEnabled ? @"enabled" : @"disabled");
}

- (NSString *)getEarthTrackingState {
    if (!_vroView) {
        return @"Stopped";
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return @"Stopped";
    }

    VROEarthTrackingState state = arSession->getEarthTrackingState();
    switch (state) {
        case VROEarthTrackingState::Enabled:
            return @"Enabled";
        case VROEarthTrackingState::Paused:
            return @"Paused";
        case VROEarthTrackingState::Stopped:
        default:
            return @"Stopped";
    }
}

- (void)getCameraGeospatialPose:(GeospatialPoseCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR view not initialized");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR session not available");
        }
        return;
    }

    VROGeospatialPose pose = arSession->getCameraGeospatialPose();

    // Check if pose is valid (latitude and longitude are non-zero)
    if (pose.latitude == 0 && pose.longitude == 0) {
        if (completionHandler) {
            completionHandler(NO, nil, @"Geospatial pose not available");
        }
        return;
    }

    NSDictionary *poseData = @{
        @"latitude": @(pose.latitude),
        @"longitude": @(pose.longitude),
        @"altitude": @(pose.altitude),
        @"heading": @(pose.heading),
        @"quaternion": @[@(pose.quaternion.X), @(pose.quaternion.Y),
                         @(pose.quaternion.Z), @(pose.quaternion.W)],
        @"horizontalAccuracy": @(pose.horizontalAccuracy),
        @"verticalAccuracy": @(pose.verticalAccuracy),
        @"headingAccuracy": @(pose.headingAccuracy),
        @"orientationYawAccuracy": @(pose.orientationYawAccuracy)
    };

    if (completionHandler) {
        completionHandler(YES, poseData, nil);
    }
}

- (void)checkVPSAvailability:(double)latitude
                   longitude:(double)longitude
           completionHandler:(VPSAvailabilityCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(@"Unknown");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(@"Unknown");
        }
        return;
    }

    arSession->checkVPSAvailability(latitude, longitude, [completionHandler](VROVPSAvailability availability) {
        NSString *availabilityString;
        switch (availability) {
            case VROVPSAvailability::Available:
                availabilityString = @"Available";
                break;
            case VROVPSAvailability::Unavailable:
                availabilityString = @"Unavailable";
                break;
            case VROVPSAvailability::Unknown:
            default:
                availabilityString = @"Unknown";
                break;
        }
        if (completionHandler) {
            completionHandler(availabilityString);
        }
    });
}

// Helper method to parse quaternion from either array [x, y, z, w] or dictionary {x, y, z, w}
- (VROQuaternion)parseQuaternion:(id)quaternion {
    VROQuaternion quat(0, 0, 0, 1); // Default identity quaternion

    if (!quaternion) {
        return quat;
    }

    @try {
        if ([quaternion isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)quaternion;
            if (arr.count >= 4) {
                quat = VROQuaternion([[arr objectAtIndex:0] floatValue],
                                     [[arr objectAtIndex:1] floatValue],
                                     [[arr objectAtIndex:2] floatValue],
                                     [[arr objectAtIndex:3] floatValue]);
            }
        } else if ([quaternion isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)quaternion;
            float x = dict[@"x"] ? [dict[@"x"] floatValue] : 0;
            float y = dict[@"y"] ? [dict[@"y"] floatValue] : 0;
            float z = dict[@"z"] ? [dict[@"z"] floatValue] : 0;
            float w = dict[@"w"] ? [dict[@"w"] floatValue] : 1;
            quat = VROQuaternion(x, y, z, w);
        }
    } @catch (NSException *exception) {
        NSLog(@"[VRTARSceneNavigator] Failed to parse quaternion, using identity: %@", exception.reason);
    }

    return quat;
}

- (void)createGeospatialAnchor:(double)latitude
                     longitude:(double)longitude
                      altitude:(double)altitude
                    quaternion:(id)quaternion
             completionHandler:(GeospatialAnchorCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR view not initialized");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR session not available");
        }
        return;
    }

    // Parse quaternion (accepts both array [x, y, z, w] and dictionary {x, y, z, w})
    VROQuaternion quat = [self parseQuaternion:quaternion];

    arSession->createGeospatialAnchor(latitude, longitude, altitude, quat,
        [completionHandler](std::shared_ptr<VROGeospatialAnchor> anchor) {
            // Success callback
            if (completionHandler) {
                VROMatrix4f transform = anchor->getTransform();
                VROVector3f position = transform.extractTranslation();

                NSDictionary *anchorData = @{
                    @"anchorId": [NSString stringWithUTF8String:anchor->getId().c_str()],
                    @"type": @"WGS84",
                    @"latitude": @(anchor->getLatitude()),
                    @"longitude": @(anchor->getLongitude()),
                    @"altitude": @(anchor->getAltitude()),
                    @"heading": @(anchor->getHeading()),
                    @"position": @[@(position.x), @(position.y), @(position.z)]
                };
                completionHandler(YES, anchorData, nil);
            }
        },
        [completionHandler](std::string error) {
            // Failure callback
            if (completionHandler) {
                NSString *errorStr = [NSString stringWithUTF8String:error.c_str()];
                completionHandler(NO, nil, errorStr);
            }
        }
    );
}

- (void)createTerrainAnchor:(double)latitude
                  longitude:(double)longitude
        altitudeAboveTerrain:(double)altitudeAboveTerrain
                  quaternion:(id)quaternion
           completionHandler:(GeospatialAnchorCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR view not initialized");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR session not available");
        }
        return;
    }

    // Parse quaternion (accepts both array [x, y, z, w] and dictionary {x, y, z, w})
    VROQuaternion quat = [self parseQuaternion:quaternion];

    arSession->createTerrainAnchor(latitude, longitude, altitudeAboveTerrain, quat,
        [completionHandler](std::shared_ptr<VROGeospatialAnchor> anchor) {
            if (completionHandler) {
                VROMatrix4f transform = anchor->getTransform();
                VROVector3f position = transform.extractTranslation();

                NSDictionary *anchorData = @{
                    @"anchorId": [NSString stringWithUTF8String:anchor->getId().c_str()],
                    @"type": @"Terrain",
                    @"latitude": @(anchor->getLatitude()),
                    @"longitude": @(anchor->getLongitude()),
                    @"altitude": @(anchor->getAltitude()),
                    @"heading": @(anchor->getHeading()),
                    @"position": @[@(position.x), @(position.y), @(position.z)]
                };
                completionHandler(YES, anchorData, nil);
            }
        },
        [completionHandler](std::string error) {
            if (completionHandler) {
                NSString *errorStr = [NSString stringWithUTF8String:error.c_str()];
                completionHandler(NO, nil, errorStr);
            }
        }
    );
}

- (void)createRooftopAnchor:(double)latitude
                  longitude:(double)longitude
       altitudeAboveRooftop:(double)altitudeAboveRooftop
                  quaternion:(id)quaternion
           completionHandler:(GeospatialAnchorCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR view not initialized");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        if (completionHandler) {
            completionHandler(NO, nil, @"AR session not available");
        }
        return;
    }

    // Parse quaternion (accepts both array [x, y, z, w] and dictionary {x, y, z, w})
    VROQuaternion quat = [self parseQuaternion:quaternion];

    arSession->createRooftopAnchor(latitude, longitude, altitudeAboveRooftop, quat,
        [completionHandler](std::shared_ptr<VROGeospatialAnchor> anchor) {
            if (completionHandler) {
                VROMatrix4f transform = anchor->getTransform();
                VROVector3f position = transform.extractTranslation();

                NSDictionary *anchorData = @{
                    @"anchorId": [NSString stringWithUTF8String:anchor->getId().c_str()],
                    @"type": @"Rooftop",
                    @"latitude": @(anchor->getLatitude()),
                    @"longitude": @(anchor->getLongitude()),
                    @"altitude": @(anchor->getAltitude()),
                    @"heading": @(anchor->getHeading()),
                    @"position": @[@(position.x), @(position.y), @(position.z)]
                };
                completionHandler(YES, anchorData, nil);
            }
        },
        [completionHandler](std::string error) {
            if (completionHandler) {
                NSString *errorStr = [NSString stringWithUTF8String:error.c_str()];
                completionHandler(NO, nil, errorStr);
            }
        }
    );
}

- (void)removeGeospatialAnchor:(NSString *)anchorId {
    if (!_vroView) {
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return;
    }

    // Find the geospatial anchor by ID and remove it
    std::string anchorIdStr = std::string([anchorId UTF8String]);
    std::unique_ptr<VROARFrame> &frame = arSession->getLastFrame();
    if (frame) {
        const std::vector<std::shared_ptr<VROARAnchor>> &anchors = frame->getAnchors();
        for (const auto &anchor : anchors) {
            if (anchor->getId() == anchorIdStr) {
                std::shared_ptr<VROGeospatialAnchor> geoAnchor =
                    std::dynamic_pointer_cast<VROGeospatialAnchor>(anchor);
                if (geoAnchor) {
                    arSession->removeGeospatialAnchor(geoAnchor);
                    break;
                }
            }
        }
    }
}

#pragma mark - Scene Semantics API Methods

- (BOOL)isSemanticModeSupported {
    if (!_vroView) {
        return NO;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return NO;
    }

    return arSession->isSemanticModeSupported();
}

- (void)setSemanticModeEnabled:(BOOL)enabled {
    _pendingSemanticModeEnabled = enabled;

    if (!_vroView) {
        _needsSemanticModeApply = YES;
        RCTLogInfo(@"[ViroAR] Scene Semantics mode queued for later: %@", enabled ? @"enabled" : @"disabled");
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        _needsSemanticModeApply = YES;
        RCTLogInfo(@"[ViroAR] Scene Semantics mode queued for later: %@", enabled ? @"enabled" : @"disabled");
        return;
    }

    [self applySemanticModeEnabled];
}

- (void)applySemanticModeEnabled {
    if (!_vroView) {
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return;
    }

    arSession->setSemanticModeEnabled(_pendingSemanticModeEnabled);
    _needsSemanticModeApply = NO;
    RCTLogInfo(@"[ViroAR] Scene Semantics mode applied: %@", _pendingSemanticModeEnabled ? @"enabled" : @"disabled");
}

- (NSDictionary *)getSemanticLabelFractions {
    NSMutableDictionary *fractions = [NSMutableDictionary new];

    if (!_vroView) {
        return fractions;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return fractions;
    }

    // Get the current frame and extract semantic fractions
    std::unique_ptr<VROARFrame> &frame = arSession->getLastFrame();
    if (!frame) {
        return fractions;
    }

    // Get fractions for all semantic labels
    NSArray *labels = @[@"unlabeled", @"sky", @"building", @"tree", @"road",
                        @"sidewalk", @"terrain", @"structure", @"object",
                        @"vehicle", @"person", @"water"];

    for (int i = 0; i < labels.count; i++) {
        VROSemanticLabel label = static_cast<VROSemanticLabel>(i);
        float fraction = frame->getSemanticLabelFraction(label);
        [fractions setObject:@(fraction) forKey:labels[i]];
    }

    return fractions;
}

- (float)getSemanticLabelFraction:(NSString *)label {
    if (!_vroView) {
        return 0.0f;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
    if (!arSession) {
        return 0.0f;
    }

    std::unique_ptr<VROARFrame> &frame = arSession->getLastFrame();
    if (!frame) {
        return 0.0f;
    }

    // Convert label string to VROSemanticLabel enum
    VROSemanticLabel semanticLabel = VROSemanticLabel::Unlabeled;
    if ([label caseInsensitiveCompare:@"unlabeled"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Unlabeled;
    } else if ([label caseInsensitiveCompare:@"sky"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Sky;
    } else if ([label caseInsensitiveCompare:@"building"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Building;
    } else if ([label caseInsensitiveCompare:@"tree"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Tree;
    } else if ([label caseInsensitiveCompare:@"road"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Road;
    } else if ([label caseInsensitiveCompare:@"sidewalk"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Sidewalk;
    } else if ([label caseInsensitiveCompare:@"terrain"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Terrain;
    } else if ([label caseInsensitiveCompare:@"structure"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Structure;
    } else if ([label caseInsensitiveCompare:@"object"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Object;
    } else if ([label caseInsensitiveCompare:@"vehicle"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Vehicle;
    } else if ([label caseInsensitiveCompare:@"person"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Person;
    } else if ([label caseInsensitiveCompare:@"water"] == NSOrderedSame) {
        semanticLabel = VROSemanticLabel::Water;
    } else {
        RCTLogWarn(@"[ViroAR] Unknown semantic label: %@", label);
        return 0.0f;
    }

    return frame->getSemanticLabelFraction(semanticLabel);
}

#pragma mark - World Mesh API Methods

- (void)setWorldMeshEnabled:(BOOL)worldMeshEnabled {
    _worldMeshEnabled = worldMeshEnabled;
    _pendingWorldMeshEnabled = worldMeshEnabled;

    if (!_vroView || !_currentScene) {
        _needsWorldMeshApply = YES;
        RCTLogInfo(@"[ViroAR] World mesh mode queued for later: %@", worldMeshEnabled ? @"enabled" : @"disabled");
        return;
    }

    [self applyWorldMeshEnabled];
}

- (void)setWorldMeshConfig:(NSDictionary *)worldMeshConfig {
    _worldMeshConfig = worldMeshConfig;

    if (worldMeshConfig) {
        // Parse config from dictionary
        if (worldMeshConfig[@"stride"]) {
            _worldMeshConfigCpp.stride = [worldMeshConfig[@"stride"] intValue];
        }
        if (worldMeshConfig[@"minConfidence"]) {
            _worldMeshConfigCpp.minConfidence = [worldMeshConfig[@"minConfidence"] floatValue];
        }
        if (worldMeshConfig[@"maxDepth"]) {
            _worldMeshConfigCpp.maxDepth = [worldMeshConfig[@"maxDepth"] floatValue];
        }
        if (worldMeshConfig[@"updateIntervalMs"]) {
            _worldMeshConfigCpp.updateIntervalMs = [worldMeshConfig[@"updateIntervalMs"] doubleValue];
        }
        if (worldMeshConfig[@"meshPersistenceMs"]) {
            _worldMeshConfigCpp.meshPersistenceMs = [worldMeshConfig[@"meshPersistenceMs"] doubleValue];
        }
        if (worldMeshConfig[@"friction"]) {
            _worldMeshConfigCpp.friction = [worldMeshConfig[@"friction"] floatValue];
        }
        if (worldMeshConfig[@"restitution"]) {
            _worldMeshConfigCpp.restitution = [worldMeshConfig[@"restitution"] floatValue];
        }
        if (worldMeshConfig[@"collisionTag"]) {
            _worldMeshConfigCpp.collisionTag = std::string([worldMeshConfig[@"collisionTag"] UTF8String]);
        }
        if (worldMeshConfig[@"debugDrawEnabled"]) {
            _worldMeshConfigCpp.debugDrawEnabled = [worldMeshConfig[@"debugDrawEnabled"] boolValue];
        }
    }

    // Apply to AR scene if ready
    if (_vroView && _currentScene) {
        std::shared_ptr<VROSceneController> sceneController = [_currentScene sceneController];
        if (sceneController) {
            std::shared_ptr<VROARScene> arScene = std::dynamic_pointer_cast<VROARScene>(sceneController->getScene());
            if (arScene) {
                arScene->setWorldMeshConfig(_worldMeshConfigCpp);
            }
        }
    }
}

- (void)applyWorldMeshEnabled {
    if (!_vroView || !_currentScene) {
        return;
    }

    std::shared_ptr<VROSceneController> sceneController = [_currentScene sceneController];
    if (!sceneController) {
        return;
    }

    std::shared_ptr<VROARScene> arScene = std::dynamic_pointer_cast<VROARScene>(sceneController->getScene());
    if (!arScene) {
        return;
    }

    // Apply config first, then enable
    arScene->setWorldMeshConfig(_worldMeshConfigCpp);
    arScene->setWorldMeshEnabled(_pendingWorldMeshEnabled);
    _needsWorldMeshApply = NO;

    RCTLogInfo(@"[ViroAR] World mesh applied: %@", _pendingWorldMeshEnabled ? @"enabled" : @"disabled");
}

#pragma mark - Monocular Depth Estimation API Methods

- (BOOL)isMonocularDepthSupported {
    if (!_vroView) {
        // Check static support without needing the view
        if (@available(iOS 14.0, *)) {
            return [VROViewAR isARSupported];
        }
        return NO;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    return [viewAR isMonocularDepthSupported];
}

- (BOOL)isMonocularDepthModelDownloaded {
    if (!_vroView) {
        return NO;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    return [viewAR isMonocularDepthModelDownloaded];
}

- (void)setMonocularDepthEnabled:(BOOL)enabled {
    if (!_vroView) {
        RCTLogWarn(@"[ViroAR] Cannot set monocular depth: AR view not initialized");
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    [viewAR setMonocularDepthEnabled:enabled];
    RCTLogInfo(@"[ViroAR] Monocular depth estimation %@", enabled ? @"enabled" : @"disabled");
}

- (void)setMonocularDepthModelURL:(NSString *)baseURL {
    if (!_vroView) {
        RCTLogWarn(@"[ViroAR] Cannot set monocular depth model URL: AR view not initialized");
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    NSURL *url = [NSURL URLWithString:baseURL];
    [viewAR setMonocularDepthModelURL:url];
    RCTLogInfo(@"[ViroAR] Monocular depth model URL set to: %@", baseURL);
}

- (void)downloadMonocularDepthModelWithProgress:(MonocularDepthDownloadProgressHandler)progressHandler
                              completionHandler:(MonocularDepthDownloadCompletionHandler)completionHandler {
    if (!_vroView) {
        if (completionHandler) {
            completionHandler(NO, @"AR view not initialized");
        }
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    [viewAR downloadMonocularDepthModelWithProgress:^(float progress) {
        if (progressHandler) {
            progressHandler(progress);
        }
    } completion:^(BOOL success, NSError *error) {
        if (completionHandler) {
            if (success) {
                completionHandler(YES, nil);
            } else {
                completionHandler(NO, error.localizedDescription ?: @"Download failed");
            }
        }
    }];
}

- (void)setPreferMonocularDepth:(BOOL)prefer {
    if (!_vroView) {
        RCTLogWarn(@"[ViroAR] Cannot set prefer monocular depth: AR view not initialized");
        return;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    [viewAR setPreferMonocularDepth:prefer];
    RCTLogInfo(@"[ViroAR] Prefer monocular depth %@", prefer ? @"enabled" : @"disabled");
}

- (BOOL)isPreferMonocularDepth {
    if (!_vroView) {
        return NO;
    }

    VROViewAR *viewAR = (VROViewAR *) _vroView;
    return [viewAR isPreferMonocularDepth];
}

#pragma mark - Frame Streaming API Methods

- (void)startFrameStream:(NSDictionary *)config {
    RCTLogInfo(@"[ViroFrameStream] Starting frame stream with config: %@", config);
    RCTLogInfo(@"[ViroFrameStream] onFrameUpdate callback is: %@", _onFrameUpdate ? @"SET" : @"NIL");

    if (!_frameCaptureService) {
        _frameCaptureService = [[VROFrameCaptureService alloc] initWithRingBufferCapacity:30];

        __weak VRTARSceneNavigator *weakSelf = self;
        _frameCaptureService.onFrameReady = ^(NSDictionary *frameData) {
            VRTARSceneNavigator *strongSelf = weakSelf;
            if (strongSelf && strongSelf.onFrameUpdate) {
                NSLog(@"[ViroFrameStream DEBUG] Forwarding frame to JS via onFrameUpdate");
                strongSelf.onFrameUpdate(frameData);
            } else {
                NSLog(@"[ViroFrameStream DEBUG] onFrameUpdate is nil! strongSelf=%@, onFrameUpdate=%@",
                      strongSelf ? @"exists" : @"nil",
                      strongSelf.onFrameUpdate ? @"exists" : @"nil");
            }
        };
    }

    // Apply configuration
    _frameCaptureService.enabled = config[@"enabled"] ? [config[@"enabled"] boolValue] : YES;
    _frameCaptureService.targetWidth = config[@"width"] ? [config[@"width"] intValue] : 640;
    _frameCaptureService.targetHeight = config[@"height"] ? [config[@"height"] intValue] : 480;
    _frameCaptureService.targetFPS = config[@"fps"] ? [config[@"fps"] floatValue] : 5.0f;
    _frameCaptureService.jpegQuality = config[@"quality"] ? [config[@"quality"] floatValue] : 0.7f;

    RCTLogInfo(@"[ViroFrameStream] Frame stream started: %dx%d @ %.1f FPS, quality: %.2f",
               _frameCaptureService.targetWidth,
               _frameCaptureService.targetHeight,
               _frameCaptureService.targetFPS,
               _frameCaptureService.jpegQuality);

    // Start timer to pump ARFrames to capture service
    // Poll at 30 FPS - the capture service's rate limiting will filter to target FPS
    [_frameStreamTimer invalidate];
    _frameStreamTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                         target:self
                                                       selector:@selector(frameStreamTimerFired:)
                                                       userInfo:nil
                                                        repeats:YES];
    RCTLogInfo(@"[ViroFrameStream] Timer started (30 FPS polling)");
}

- (void)stopFrameStream {
    RCTLogInfo(@"[ViroFrameStream] Stopping frame stream");

    // Invalidate timer first
    [_frameStreamTimer invalidate];
    _frameStreamTimer = nil;

    if (_frameCaptureService) {
        _frameCaptureService.enabled = NO;
    }
}

#pragma mark - Frame Stream Timer

- (void)frameStreamTimerFired:(NSTimer *)timer {
    if (!_frameCaptureService || !_frameCaptureService.enabled) {
        return;
    }

    ARSession *session = [self getNativeARSession];
    if (!session) {
        return;
    }

    ARFrame *frame = session.currentFrame;
    if (frame) {
        [_frameCaptureService onARFrame:frame session:session];
    }
}

- (void)resolveDetections:(NSString *)frameId
                   points:(NSArray<NSDictionary *> *)points
        completionHandler:(void (^)(NSDictionary * _Nonnull result))completionHandler {

    if (!_frameCaptureService) {
        if (completionHandler) {
            completionHandler(@{
                @"frameId": frameId ?: @"",
                @"results": @[],
                @"error": @"Frame capture service not initialized"
            });
        }
        return;
    }

    VROFrameEntry *entry = [_frameCaptureService frameEntryForId:frameId];

    if (!entry) {
        RCTLogWarn(@"[ViroFrameStream] Frame not found in ring buffer: %@", frameId);
        if (completionHandler) {
            completionHandler(@{
                @"frameId": frameId ?: @"",
                @"results": @[],
                @"error": @"Frame not found in ring buffer (may have been evicted)"
            });
        }
        return;
    }

    ARSession *session = [self getNativeARSession];
    if (!session) {
        if (completionHandler) {
            completionHandler(@{
                @"frameId": frameId,
                @"results": @[],
                @"error": @"AR session not available"
            });
        }
        return;
    }

    // Resolve detections on background thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<VRODetectionResult *> *results =
            [VRODetectionResolver resolvePoints:points
                                     frameEntry:entry
                                      arSession:session];

        // Convert results to dictionary format
        NSMutableArray *resultsArray = [NSMutableArray arrayWithCapacity:results.count];
        for (VRODetectionResult *r in results) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"input"] = @{@"x": @(r.inputX), @"y": @(r.inputY)};
            dict[@"ok"] = @(r.ok);

            if (r.ok) {
                dict[@"worldPos"] = @[@(r.worldPos.x), @(r.worldPos.y), @(r.worldPos.z)];
                dict[@"confidence"] = @(r.confidence);
                dict[@"method"] = r.method ?: @"unknown";
            } else if (r.error) {
                dict[@"error"] = r.error;
            }

            [resultsArray addObject:dict];
        }

        // Return result on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionHandler) {
                completionHandler(@{
                    @"frameId": frameId,
                    @"results": resultsArray
                });
            }
        });
    });
}

#pragma mark - VRORenderDelegate Frame Streaming Hook

- (void)userDidRequestExitVR {
    // Not used for AR
}

- (void)willRenderFrame:(std::shared_ptr<VRORenderer>)renderer
                context:(std::shared_ptr<VRORenderContext>)context
                 driver:(std::shared_ptr<VRODriver>)driver {
    ARSession *session = [self getNativeARSession];
    if (session) {
        ARFrame *frame = session.currentFrame;
        if (frame) {
            // Fan-out AR frames to capture service for streaming
            if (_frameCaptureService && _frameCaptureService.enabled) {
                [_frameCaptureService onARFrame:frame session:session];
            }

            // Debug log every ~60 frames (roughly once per second at 60fps)
            static int frameCount = 0;
            frameCount++;
            if (frameCount % 60 == 1) {
                RCTLogInfo(@"[ViroAR] willRenderFrame: callback=%s mappingStatus=%ld trackingState=%ld",
                           _onWorldMappingStatusChanged ? "SET" : "NIL",
                           (long)frame.worldMappingStatus,
                           (long)frame.camera.trackingState);
            }

            // Check for world mapping status changes and fire callback if changed
            if (_onWorldMappingStatusChanged) {
                ARWorldMappingStatus currentMappingStatus = frame.worldMappingStatus;
                ARTrackingState currentTrackingState = frame.camera.trackingState;

                BOOL statusChanged = NO;
                if (!_worldMappingStatusInitialized) {
                    // First time - always fire to give initial state
                    _worldMappingStatusInitialized = YES;
                    statusChanged = YES;
                } else if (currentMappingStatus != _lastWorldMappingStatus ||
                           currentTrackingState != _lastTrackingState) {
                    statusChanged = YES;
                }

                if (statusChanged) {
                    _lastWorldMappingStatus = currentMappingStatus;
                    _lastTrackingState = currentTrackingState;

                    // Convert to string values
                    NSString *mappingStr;
                    switch (currentMappingStatus) {
                        case ARWorldMappingStatusNotAvailable: mappingStr = @"notAvailable"; break;
                        case ARWorldMappingStatusLimited: mappingStr = @"limited"; break;
                        case ARWorldMappingStatusExtending: mappingStr = @"extending"; break;
                        case ARWorldMappingStatusMapped: mappingStr = @"mapped"; break;
                    }

                    NSString *trackingStr;
                    switch (currentTrackingState) {
                        case ARTrackingStateNotAvailable: trackingStr = @"notAvailable"; break;
                        case ARTrackingStateLimited: trackingStr = @"limited"; break;
                        case ARTrackingStateNormal: trackingStr = @"normal"; break;
                    }

                    BOOL canSave = (currentTrackingState == ARTrackingStateNormal) &&
                                   (currentMappingStatus == ARWorldMappingStatusMapped ||
                                    currentMappingStatus == ARWorldMappingStatusExtending);

                    RCTLogInfo(@"[ViroAR] World mapping status CHANGED: mapping=%@ tracking=%@ canSave=%@",
                               mappingStr, trackingStr, canSave ? @"YES" : @"NO");

                    _onWorldMappingStatusChanged(@{
                        @"mappingStatus": mappingStr,
                        @"trackingState": trackingStr,
                        @"canSave": @(canSave)
                    });
                }
            }
        }
    }
}

- (void)didRenderFrame:(std::shared_ptr<VRORenderer>)renderer
               context:(std::shared_ptr<VRORenderContext>)context
                driver:(std::shared_ptr<VRODriver>)driver {
    // No-op for AR scene navigator
}

#pragma mark - World Map Persistence Methods (Imperative API)

// Sanitize sessionId for safe filename usage
- (NSString *)sanitizedSessionId:(NSString *)sessionId {
    if (!sessionId || sessionId.length == 0) {
        return @"default";
    }

    // Strip path traversal
    NSString *safe = [sessionId stringByReplacingOccurrencesOfString:@".." withString:@""];

    // Allow only [A-Za-z0-9._-], replace everything else
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"];
    for (NSUInteger i = 0; i < safe.length; i++) {
        unichar c = [safe characterAtIndex:i];
        [result appendString:[allowed characterIsMember:c] ?
            [NSString stringWithCharacters:&c length:1] : @"_"];
    }

    // Enforce max length (100 chars)
    if (result.length > 100) {
        result = [[result substringToIndex:100] mutableCopy];
    }

    // Handle empty result (e.g., sessionId was all special chars)
    if (result.length == 0) {
        return @"default";
    }

    return result;
}

// Get file path for a given sessionId
- (NSString *)worldMapFilePathForSession:(NSString *)sessionId {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDirectory = [paths firstObject];
    NSString *worldMapsDirectory = [cachesDirectory stringByAppendingPathComponent:@"ViroARWorldMaps"];

    // Create directory if it doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:worldMapsDirectory]) {
        NSError *error;
        [fileManager createDirectoryAtPath:worldMapsDirectory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:&error];
        if (error) {
            RCTLogError(@"[ViroAR] Failed to create world maps directory: %@", error.localizedDescription);
            return nil;
        }
    }

    NSString *sanitized = [self sanitizedSessionId:sessionId];
    return [worldMapsDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.arworldmap", sanitized]];
}

- (void)saveWorldMapForSession:(NSString *)sessionId
                      filePath:(NSString * _Nullable)customFilePath
             completionHandler:(WorldMapCompletionHandler)completionHandler {
    // Concurrency check
    if (_worldMapOpInFlight != VRTWorldMapOpNone) {
        if (completionHandler) {
            completionHandler(NO, @"BUSY", @"Another world map operation is in progress", nil);
        }
        return;
    }

    ARSession *session = [self getNativeARSession];
    if (!session) {
        if (completionHandler) {
            completionHandler(NO, @"SESSION_UNAVAILABLE", @"AR session not available", nil);
        }
        return;
    }

    // Check tracking state and world mapping status
    ARFrame *frame = session.currentFrame;

    // Convert status values to strings for logging/error messages
    NSString *mappingStr = @"nil";
    NSString *trackingStr = @"nil";
    if (frame) {
        switch (frame.worldMappingStatus) {
            case ARWorldMappingStatusNotAvailable: mappingStr = @"notAvailable"; break;
            case ARWorldMappingStatusLimited: mappingStr = @"limited"; break;
            case ARWorldMappingStatusExtending: mappingStr = @"extending"; break;
            case ARWorldMappingStatusMapped: mappingStr = @"mapped"; break;
        }
        switch (frame.camera.trackingState) {
            case ARTrackingStateNotAvailable: trackingStr = @"notAvailable"; break;
            case ARTrackingStateLimited: trackingStr = @"limited"; break;
            case ARTrackingStateNormal: trackingStr = @"normal"; break;
        }
    }

    RCTLogInfo(@"[ViroAR] saveWorldMap check: frame=%s mappingStatus=%@ trackingState=%@",
               frame ? "valid" : "nil", mappingStr, trackingStr);

    if (!frame ||
        frame.camera.trackingState != ARTrackingStateNormal ||
        (frame.worldMappingStatus != ARWorldMappingStatusMapped &&
         frame.worldMappingStatus != ARWorldMappingStatusExtending)) {
        if (completionHandler) {
            NSString *errorMsg = [NSString stringWithFormat:
                @"Cannot save: frame=%s trackingState=%@ mappingStatus=%@ (need trackingState=normal AND mappingStatus=mapped or extending)",
                frame ? "valid" : "nil", trackingStr, mappingStr];
            completionHandler(NO, @"WORLD_MAP_NOT_READY", errorMsg, nil);
        }
        return;
    }

    _worldMapOpInFlight = VRTWorldMapOpSaving;

    // Use custom path if provided, otherwise compute from sessionId
    NSString *targetFilePath = customFilePath;

    __weak VRTARSceneNavigator *weakSelf = self;
    [session getCurrentWorldMapWithCompletionHandler:^(ARWorldMap *worldMap, NSError *error) {
        VRTARSceneNavigator *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (!worldMap) {
            strongSelf->_worldMapOpInFlight = VRTWorldMapOpNone;
            NSString *errorMsg = error.localizedDescription ?: @"World map not available";
            if (completionHandler) {
                completionHandler(NO, @"WORLD_MAP_NOT_READY", errorMsg, nil);
            }
            return;
        }

        // Determine file path: use custom path or compute from sessionId
        NSString *filePath = targetFilePath ?: [strongSelf worldMapFilePathForSession:sessionId];
        if (!filePath) {
            strongSelf->_worldMapOpInFlight = VRTWorldMapOpNone;
            if (completionHandler) {
                completionHandler(NO, @"SESSION_UNAVAILABLE", @"Failed to get file path", nil);
            }
            return;
        }

        NSError *archiveError;
        NSData *mapData = [NSKeyedArchiver archivedDataWithRootObject:worldMap
                                               requiringSecureCoding:YES
                                                               error:&archiveError];
        if (!mapData) {
            strongSelf->_worldMapOpInFlight = VRTWorldMapOpNone;
            NSString *errorMsg = archiveError.localizedDescription ?: @"Failed to archive world map";
            if (completionHandler) {
                completionHandler(NO, @"DECODE_FAILED", errorMsg, nil);
            }
            return;
        }

        NSError *writeError;
        BOOL success = [mapData writeToFile:filePath options:NSDataWritingAtomic error:&writeError];
        strongSelf->_worldMapOpInFlight = VRTWorldMapOpNone;

        if (!success) {
            NSString *errorMsg = writeError.localizedDescription ?: @"Failed to write world map file";
            if (completionHandler) {
                completionHandler(NO, @"SESSION_UNAVAILABLE", errorMsg, nil);
            }
            return;
        }

        RCTLogInfo(@"[ViroAR] World map saved for session: %@ at path: %@", sessionId, filePath);
        if (completionHandler) {
            completionHandler(YES, nil, nil, filePath);
        }
    }];
}

- (void)loadWorldMapForSession:(NSString *)sessionId
                      filePath:(NSString * _Nullable)customFilePath
             completionHandler:(WorldMapCompletionHandler)completionHandler {
    // Concurrency check
    if (_worldMapOpInFlight != VRTWorldMapOpNone) {
        if (completionHandler) {
            completionHandler(NO, @"BUSY", @"Another world map operation is in progress", nil);
        }
        return;
    }

    // Determine file path: use custom path or compute from sessionId
    NSString *filePath = customFilePath;
    if (!filePath || filePath.length == 0) {
        filePath = [self worldMapFilePathForSession:sessionId];
    }

    if (!filePath) {
        if (completionHandler) {
            completionHandler(NO, @"SESSION_UNAVAILABLE", @"Failed to get file path", nil);
        }
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) {
        if (completionHandler) {
            NSString *errorMsg = customFilePath
                ? @"No file found at the specified path"
                : @"No saved world map found for this session";
            completionHandler(NO, @"NOT_FOUND", errorMsg, nil);
        }
        return;
    }

    ARSession *session = [self getNativeARSession];
    if (!session) {
        if (completionHandler) {
            completionHandler(NO, @"SESSION_UNAVAILABLE", @"AR session not available", nil);
        }
        return;
    }

    _worldMapOpInFlight = VRTWorldMapOpLoading;

    NSError *readError;
    NSData *mapData = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];
    if (!mapData) {
        _worldMapOpInFlight = VRTWorldMapOpNone;
        if (completionHandler) {
            completionHandler(NO, @"DECODE_FAILED",
                readError.localizedDescription ?: @"Failed to read world map file", nil);
        }
        return;
    }

    NSError *decodeError;
    ARWorldMap *worldMap = [NSKeyedUnarchiver unarchivedObjectOfClass:[ARWorldMap class]
                                                             fromData:mapData
                                                                error:&decodeError];
    if (!worldMap) {
        _worldMapOpInFlight = VRTWorldMapOpNone;
        if (completionHandler) {
            completionHandler(NO, @"DECODE_FAILED",
                decodeError.localizedDescription ?: @"Failed to decode world map", nil);
        }
        return;
    }

    // Create new configuration, preserving current config settings if available
    ARWorldTrackingConfiguration *newConfig = [[ARWorldTrackingConfiguration alloc] init];

    // Type-check before copying from current config
    if ([session.configuration isKindOfClass:[ARWorldTrackingConfiguration class]]) {
        ARWorldTrackingConfiguration *currentConfig = (ARWorldTrackingConfiguration *)session.configuration;

        // Copy relevant fields
        newConfig.planeDetection = currentConfig.planeDetection;
        newConfig.environmentTexturing = currentConfig.environmentTexturing;
        newConfig.autoFocusEnabled = currentConfig.autoFocusEnabled;
        newConfig.lightEstimationEnabled = currentConfig.lightEstimationEnabled;

        // frameSemantics only if supported and previously enabled
        if (currentConfig.frameSemantics != ARFrameSemanticNone &&
            [ARWorldTrackingConfiguration supportsFrameSemantics:currentConfig.frameSemantics]) {
            newConfig.frameSemantics = currentConfig.frameSemantics;
        }
    } else {
        // Fallback to defaults from instance properties
        newConfig.autoFocusEnabled = _autofocus;
    }

    newConfig.initialWorldMap = worldMap;
    [session runWithConfiguration:newConfig
                          options:ARSessionRunOptionResetTracking | ARSessionRunOptionRemoveExistingAnchors];

    _worldMapOpInFlight = VRTWorldMapOpNone;

    RCTLogInfo(@"[ViroAR] World map loaded for session: %@ from path: %@", sessionId, filePath);
    if (completionHandler) {
        completionHandler(YES, nil, nil, nil);
    }
}

- (void)deleteWorldMapForSession:(NSString *)sessionId
               completionHandler:(WorldMapCompletionHandler)completionHandler {
    // Concurrency check
    if (_worldMapOpInFlight != VRTWorldMapOpNone) {
        if (completionHandler) {
            completionHandler(NO, @"BUSY", @"Another world map operation is in progress", nil);
        }
        return;
    }

    NSString *filePath = [self worldMapFilePathForSession:sessionId];
    if (!filePath) {
        if (completionHandler) {
            completionHandler(NO, @"SESSION_UNAVAILABLE", @"Failed to get file path", nil);
        }
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) {
        if (completionHandler) {
            completionHandler(NO, @"NOT_FOUND", @"No saved world map found for this session", nil);
        }
        return;
    }

    _worldMapOpInFlight = VRTWorldMapOpDeleting;

    NSError *deleteError;
    BOOL success = [fileManager removeItemAtPath:filePath error:&deleteError];

    _worldMapOpInFlight = VRTWorldMapOpNone;

    if (!success) {
        if (completionHandler) {
            completionHandler(NO, @"SESSION_UNAVAILABLE",
                deleteError.localizedDescription ?: @"Failed to delete world map file", nil);
        }
        return;
    }

    RCTLogInfo(@"[ViroAR] World map deleted for session: %@", sessionId);
    if (completionHandler) {
        completionHandler(YES, nil, nil, nil);
    }
}

- (void)getWorldMappingStatusWithCompletionHandler:(void (^)(NSDictionary *result))completionHandler {
    if (!completionHandler) {
        return;
    }

    ARSession *session = [self getNativeARSession];
    if (!session || !session.currentFrame) {
        completionHandler(@{
            @"mappingStatus": @"notAvailable",
            @"trackingState": @"notAvailable",
            @"canSave": @NO
        });
        return;
    }

    ARFrame *frame = session.currentFrame;

    NSString *mappingStr;
    switch (frame.worldMappingStatus) {
        case ARWorldMappingStatusNotAvailable: mappingStr = @"notAvailable"; break;
        case ARWorldMappingStatusLimited: mappingStr = @"limited"; break;
        case ARWorldMappingStatusExtending: mappingStr = @"extending"; break;
        case ARWorldMappingStatusMapped: mappingStr = @"mapped"; break;
    }

    NSString *trackingStr;
    switch (frame.camera.trackingState) {
        case ARTrackingStateNotAvailable: trackingStr = @"notAvailable"; break;
        case ARTrackingStateLimited: trackingStr = @"limited"; break;
        case ARTrackingStateNormal: trackingStr = @"normal"; break;
    }

    BOOL canSave = (frame.camera.trackingState == ARTrackingStateNormal) &&
                   (frame.worldMappingStatus == ARWorldMappingStatusMapped ||
                    frame.worldMappingStatus == ARWorldMappingStatusExtending);

    completionHandler(@{
        @"mappingStatus": mappingStr,
        @"trackingState": trackingStr,
        @"canSave": @(canSave)
    });
}

#pragma mark RCTInvalidating methods

- (void)invalidate {
    // Stop frame stream timer
    [_frameStreamTimer invalidate];
    _frameStreamTimer = nil;

    if (_vroView) {
        // pause the view before removing it.
        VROViewAR *viewAR = (VROViewAR *)_vroView;
        [viewAR setPaused:YES];

        // Properly terminate the AR session and clean up GL resources
        @try {
            std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
            if (arSession) {
                arSession->pause();
            }
            // Always call deleteGL to ensure proper resource cleanup
            [viewAR deleteGL];
        } @catch (NSException *exception) {
            NSLog(@"Error terminating AR session during invalidate: %@", exception.reason);
        }
    }

    // Destroy the EAGLContext to release GPU resources
    if (_eaglContext) {
        if ([EAGLContext currentContext] == _eaglContext) {
            [EAGLContext setCurrentContext:nil];
        }
        _eaglContext = nil;
    }

    //NOTE: DO NOT NULL OUT _currentViews here, that will cause a memory leak and prevent child views from being released.
    _currentScene = nil;
    _vroView = nil;
    _childViews = nil;
}
@end
