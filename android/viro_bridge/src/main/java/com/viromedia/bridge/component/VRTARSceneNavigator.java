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

package com.viromedia.bridge.component;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;

import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.viro.core.ARAnchor;
import com.viro.core.ARNode;
import com.viro.core.ARScene;
import com.viro.core.ViroViewARCore;
import com.viro.core.ViroView;
import com.viromedia.bridge.ReactViroPackage;
import com.viromedia.bridge.component.node.VRTARScene;
import com.viromedia.bridge.module.ARSceneNavigatorModule;
import com.viromedia.bridge.utility.ARUtils;
import com.viromedia.bridge.utility.DisplayRotationListener;

import java.lang.ref.WeakReference;

/**
 * ARSceneNavigator manages the various AR scenes that a Viro App can navigate between.
 */
public class VRTARSceneNavigator extends VRT3DSceneNavigator {

    private DisplayRotationListener mRotationListener;
    private boolean mAutoFocusEnabled = false;
    private boolean mNeedsAutoFocusToggle = false;
    private ARScene.OcclusionMode mOcclusionMode = ARScene.OcclusionMode.DISABLED;

    private static class StartupListenerARCore implements ViroViewARCore.StartupListener {

        private WeakReference<VRTARSceneNavigator> mNavigator;

        public StartupListenerARCore(VRTARSceneNavigator navigator) {
            mNavigator = new WeakReference<VRTARSceneNavigator>(navigator);
        }

        @Override
        public void onSuccess() {
            final VRTARSceneNavigator navigator = mNavigator.get();
            final WeakReference<VRTARSceneNavigator> navigatorWeakReference =
                    new WeakReference<VRTARSceneNavigator>(navigator);

            if (navigator == null) {
                return;
            }

            navigator.mGLInitialized = true;
            (new Handler(Looper.getMainLooper())).post(new Runnable() {
                @Override
                public void run() {
                    VRTARSceneNavigator nav = navigatorWeakReference.get();
                    if (nav != null) {
                        nav.mGLInitialized = true;
                        nav.setViroContext();
                    }
                }
            });

            if (navigator.mNeedsAutoFocusToggle) {
                navigator.setAutoFocusEnabled(navigator.mAutoFocusEnabled);
                navigator.mNeedsAutoFocusToggle = false;
            }
        }

        @Override
        public void onFailure(ViroViewARCore.StartupError error, String errorMessage) {
            Log.e("Viro", "onRendererFailed [error: " + error + "], message [" + errorMessage + "]");
            // No-op
        }
    }

    public VRTARSceneNavigator(ReactContext context) {
        super(context, ReactViroPackage.ViroPlatform.AR);
        final  WeakReference<VRTARSceneNavigator> weakSceneARRef = new WeakReference<VRTARSceneNavigator>(this);
        mRotationListener = new DisplayRotationListener(context) {
            @Override
            public void onDisplayRotationChanged(int rotation) {
                VRTARSceneNavigator navigator = weakSceneARRef.get();
                if (navigator != null) {
                    ViroViewARCore view = navigator.getARView();
                    if (view != null) {
                        view.setCameraRotation(rotation);
                    }
                }
            }
        };
        mRotationListener.enable();
    }

    /*
     Override the parent method to use the ViroARView.
     */
    @Override
    protected ViroView createViroView(ReactContext reactContext) {
        return new ViroViewARCore(reactContext.getCurrentActivity(),
                new StartupListenerARCore(this));
    }

    @Override
    public void addView(View child, int index) {
        // This view only accepts ARScene and VrView children!
        if (!(child instanceof VRTARScene) && !(child instanceof ViroView)) {
            throw new IllegalArgumentException("Attempted to add a non-ARScene element ["
                    + child.getClass().getSimpleName() + "] to ARSceneNavigator!");
        }
        super.addView(child, index);

        // Apply current occlusion mode to newly added ARScenes
        if (child instanceof VRTARScene) {
            ((VRTARScene) child).setOcclusionMode(mOcclusionMode);
        }
    }

    public ViroViewARCore getARView() {
        return (ViroViewARCore) mViroView;
    }

    public void resetARSession() {
        ViroViewARCore arView = getARView();
        // No-op for now.
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        if (mRotationListener != null) {
            mRotationListener.disable();
        }
    }

    public void setAutoFocusEnabled(boolean enabled) {
        mAutoFocusEnabled = enabled;
        if (mGLInitialized) {
            ((ViroViewARCore)mViroView).setCameraAutoFocusEnabled(mAutoFocusEnabled);
        } else {
            mNeedsAutoFocusToggle = true;
        }
    }

    public void setOcclusionMode(String mode) {
        mOcclusionMode = ARScene.OcclusionMode.DISABLED;
        if (mode != null) {
            switch (mode.toLowerCase()) {
                case "depthbased":
                    mOcclusionMode = ARScene.OcclusionMode.DEPTH_BASED;
                    break;
                case "peopleonly":
                    mOcclusionMode = ARScene.OcclusionMode.PEOPLE_ONLY;
                    break;
                case "disabled":
                default:
                    mOcclusionMode = ARScene.OcclusionMode.DISABLED;
                    break;
            }
        }
        // Note: Occlusion mode will be applied to scenes when they are added via addView()
    }

    /**
     * Get the current occlusion mode. Used when adding new scenes so they
     * inherit the navigator's occlusion setting.
     */
    public ARScene.OcclusionMode getOcclusionMode() {
        return mOcclusionMode;
    }

    // Cloud Anchor Support

    private String mCloudAnchorProvider = "none";
    private static final String TAG = "ViroAR";

    public void setCloudAnchorProvider(String provider) {
        mCloudAnchorProvider = provider != null ? provider.toLowerCase() : "none";

        Log.i(TAG, "Setting cloud anchor provider: " + mCloudAnchorProvider);

        if ("arcore".equals(mCloudAnchorProvider)) {
            Log.i(TAG, "ARCore Cloud Anchors provider enabled");

            // Check if API key is configured in AndroidManifest
            try {
                android.content.pm.ApplicationInfo ai = getContext().getPackageManager()
                    .getApplicationInfo(getContext().getPackageName(), android.content.pm.PackageManager.GET_META_DATA);
                if (ai.metaData != null) {
                    String apiKey = ai.metaData.getString("com.google.android.ar.API_KEY");
                    if (apiKey != null && !apiKey.isEmpty()) {
                        Log.i(TAG, "ARCore API key found in AndroidManifest.xml (length: " + apiKey.length() + ")");
                    } else {
                        Log.w(TAG, "WARNING: com.google.android.ar.API_KEY not found in AndroidManifest.xml. Cloud anchors will not work!");
                    }
                } else {
                    Log.w(TAG, "WARNING: No meta-data found in AndroidManifest.xml. Cloud anchors may not work!");
                }
            } catch (Exception e) {
                Log.w(TAG, "Could not check for ARCore API key: " + e.getMessage());
            }
        } else {
            Log.i(TAG, "Cloud Anchors disabled");
        }
    }

    /**
     * Get the current ARScene from the active VRTARScene child.
     */
    private ARScene getCurrentARScene() {
        VRTARScene currentScene = null;
        for (int i = 0; i < getChildCount(); i++) {
            View child = getChildAt(i);
            if (child instanceof VRTARScene) {
                currentScene = (VRTARScene) child;
                break;
            }
        }
        if (currentScene != null) {
            return (ARScene) currentScene.getNativeScene();
        }
        return null;
    }

    public void hostCloudAnchor(String anchorId, int ttlDays,
                                ARSceneNavigatorModule.CloudAnchorCallback callback) {
        if (!"arcore".equals(mCloudAnchorProvider)) {
            callback.onFailure("Cloud anchor provider not configured. Set cloudAnchorProvider='arcore' to enable.",
                               "ErrorInternal");
            return;
        }

        ARScene arScene = getCurrentARScene();
        if (arScene == null) {
            callback.onFailure("AR scene not available", "ErrorInternal");
            return;
        }

        // Host the anchor using ARCore's cloud anchor API
        // The native layer handles anchor lookup by ID
        arScene.hostCloudAnchorById(anchorId, ttlDays, new ARScene.CloudAnchorHostListener() {
            @Override
            public void onSuccess(ARAnchor cloudAnchor, ARNode arNode) {
                // Get the cloud anchor ID from the returned anchor
                callback.onSuccess(cloudAnchor.getCloudAnchorId());
            }

            @Override
            public void onFailure(String error) {
                callback.onFailure(error, "ErrorInternal");
            }
        });
    }

    public void resolveCloudAnchor(String cloudAnchorId,
                                   ARSceneNavigatorModule.CloudAnchorResolveCallback callback) {
        if (!"arcore".equals(mCloudAnchorProvider)) {
            callback.onFailure("Cloud anchor provider not configured. Set cloudAnchorProvider='arcore' to enable.",
                               "ErrorInternal");
            return;
        }

        ARScene arScene = getCurrentARScene();
        if (arScene == null) {
            callback.onFailure("AR scene not available", "ErrorInternal");
            return;
        }

        // Resolve the cloud anchor
        arScene.resolveCloudAnchor(cloudAnchorId, new ARScene.CloudAnchorResolveListener() {
            @Override
            public void onSuccess(ARAnchor anchor, ARNode arNode) {
                // Convert anchor to WritableMap using ARUtils
                WritableMap anchorData = ARUtils.mapFromARAnchor(anchor);
                callback.onSuccess(anchorData);
            }

            @Override
            public void onFailure(String error) {
                callback.onFailure(error, "ErrorInternal");
            }
        });
    }

    public void cancelCloudAnchorOperations() {
        // ARCore doesn't have explicit cancel - operations will just time out
        // This is a placeholder for future implementation if needed
    }
}
