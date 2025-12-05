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

#import <ViroKit/ViroKit.h>
#import "VRTARSceneNavigator.h"
#import <React/RCTAssert.h>
#import <React/RCTLog.h>
#import "VRTARScene.h"
#import "VRTNotifications.h"
#import <React/RCTRootView.h>
#import <React/RCTUtils.h>
#import "VRTPerfMonitor.h"
#import "VRTMaterialManager.h"

@implementation VRTARSceneNavigator {
    id <VROView> _vroView;
    NSInteger _currentStackPosition;
    RCTBridge *_bridge;
    VROVideoQuality _vroVideoQuality;
    BOOL _hasCleanedUp;
    EAGLContext *_eaglContext;
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
    }
    return self;
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

- (void)didSetProps:(NSArray<NSString *> *)changedProps {
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

#pragma mark - Cloud Anchor Methods

- (void)setCloudAnchorProvider:(NSString *)cloudAnchorProvider {
    _cloudAnchorProvider = cloudAnchorProvider;
    if (_vroView) {
        VROViewAR *viewAR = (VROViewAR *) _vroView;
        std::shared_ptr<VROARSession> arSession = [viewAR getARSession];
        if (arSession) {
            if ([cloudAnchorProvider caseInsensitiveCompare:@"arcore"] == NSOrderedSame) {
                arSession->setCloudAnchorProvider(VROCloudAnchorProvider::ARCore);
            } else {
                arSession->setCloudAnchorProvider(VROCloudAnchorProvider::None);
            }
        }
    }
}

- (void)hostCloudAnchor:(NSString *)anchorId
                ttlDays:(NSInteger)ttlDays
      completionHandler:(CloudAnchorHostCompletionHandler)completionHandler {
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

    // Find the anchor by ID
    std::string anchorIdStr = std::string([anchorId UTF8String]);
    std::shared_ptr<VROARAnchor> anchor = nullptr;

    // Search through frame anchors
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
            completionHandler(NO, nil, @"Anchor not found in session", @"ErrorCloudIdNotFound");
        }
        return;
    }

    // Host the anchor with TTL
    arSession->hostCloudAnchor(anchor,
        (int)ttlDays,
        [completionHandler](std::shared_ptr<VROARAnchor> hostedAnchor) {
            // Success callback
            if (completionHandler) {
                NSString *cloudId = [NSString stringWithUTF8String:hostedAnchor->getCloudAnchorId().c_str()];
                completionHandler(YES, cloudId, nil, @"Success");
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

#pragma mark RCTInvalidating methods

- (void)invalidate {
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
