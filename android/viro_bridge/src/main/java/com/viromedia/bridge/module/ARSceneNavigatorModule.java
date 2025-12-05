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

package com.viromedia.bridge.module;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import androidx.core.content.ContextCompat;
import android.util.Log;
import android.view.PixelCopy;
import android.view.View;

import com.facebook.react.ReactActivity;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.PermissionListener;
import com.facebook.react.uimanager.IllegalViewOperationException;
import com.facebook.react.bridge.UIManager;
import com.facebook.react.fabric.FabricUIManager;
import com.facebook.react.uimanager.UIManagerHelper;
import com.facebook.react.module.annotations.ReactModule;
import com.viro.core.Vector;
import com.viro.core.ViroMediaRecorder;
import com.viro.core.ViroMediaRecorder.Error;
import com.viro.core.ViroViewARCore;
import com.viromedia.bridge.component.VRTARSceneNavigator;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

@ReactModule(name = "VRTARSceneNavigatorModule")
public class ARSceneNavigatorModule extends ReactContextBaseJavaModule {
    private static final int UNSUPPORTED_PLATFORM_ERROR = 6;
    private static final String RECORDING_SUCCESS_KEY = "success";
    private static final String RECORDING_URL_KEY = "url";
    private static final String RECORDING_ERROR_KEY = "errorCode";
    private static final int PERMISSION_REQ_CODE_AUDIO = 1;
    private static final int PERMISSION_REQ_CODE_STORAGE = 2;

    private ReactApplicationContext mContext;
    // https://stackoverflow.com/a/44879687
    @Override
    public boolean canOverrideExistingModule() {
        return true;
    }
    public ARSceneNavigatorModule(ReactApplicationContext context) {
        super(context);
        mContext = context;
    }

    @Override
    public String getName() {
        return "VRTARSceneNavigatorModule";
    }

    @ReactMethod
    public void startVideoRecording(final int sceneNavTag, final String fileName,
                                    final boolean saveToCameraRool, final Callback reactErrorDelegate) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            reactErrorDelegate.invoke(UNSUPPORTED_PLATFORM_ERROR);
            return;
        }
        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View sceneView = viewResolver.resolveView(sceneNavTag);
                if (!(sceneView instanceof VRTARSceneNavigator)) {
                    throw new IllegalViewOperationException("Viro: Attempted to call startVideoRecording on a non-ARSceneNav view!");
                }
                VRTARSceneNavigator scene = (VRTARSceneNavigator) sceneView;

                // Grab the recorder from the ar scene view
                final ViroMediaRecorder recorder = scene.getARView().getRecorder();
                if (recorder == null){
                    reactErrorDelegate.invoke(UNSUPPORTED_PLATFORM_ERROR);
                    return;
                }

                // Construct an error listener callback that may be triggered during recording.
                final ViroMediaRecorder.RecordingErrorListener viroErrorDelegate = new ViroMediaRecorder.RecordingErrorListener() {
                    @Override
                    public void onRecordingFailed(Error error) {
                        reactErrorDelegate.invoke(error.toInt());
                    }
                };

                // Start recording if we have the right permissions
                checkPermissionsAndRun(new PermissionListener() {
                    @Override
                    public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
                        recorder.startRecordingAsync(fileName, saveToCameraRool, viroErrorDelegate);
                        return true;
                    }
                }, true);
            }
        });
    }

    @ReactMethod
    public void stopVideoRecording(final int sceneNavTag, final Promise promise) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            WritableMap returnMap = Arguments.createMap();
            returnMap.putBoolean(RECORDING_SUCCESS_KEY, false);
            returnMap.putInt(RECORDING_ERROR_KEY, UNSUPPORTED_PLATFORM_ERROR);
            returnMap.putString(RECORDING_URL_KEY, null);
            promise.resolve(returnMap);
            return;
        }
        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View sceneView = viewResolver.resolveView(sceneNavTag);
                if (!(sceneView instanceof VRTARSceneNavigator)) {
                    throw new IllegalViewOperationException("Viro: Attempted to call startVideoRecording on a non-ARSceneNav view!");
                }
                VRTARSceneNavigator scene = (VRTARSceneNavigator) sceneView;

                // Grab the recorder from the ar scene view
                final ViroMediaRecorder recorder = scene.getARView().getRecorder();
                if (recorder == null){
                    WritableMap returnMap = Arguments.createMap();
                    returnMap.putBoolean(RECORDING_SUCCESS_KEY, false);
                    returnMap.putInt(RECORDING_ERROR_KEY, UNSUPPORTED_PLATFORM_ERROR);
                    returnMap.putString(RECORDING_URL_KEY, null);
                    promise.resolve(returnMap);
                    return;
                }

                // Construct a completion delegate callback to be notified of the result of the recording.
                final ViroMediaRecorder.VideoRecordingFinishListener completionCallback =
                        new ViroMediaRecorder.VideoRecordingFinishListener() {
                    @Override
                    public void onError(Error error) {
                        WritableMap returnMap = Arguments.createMap();
                        returnMap.putBoolean(RECORDING_SUCCESS_KEY, false);
                        returnMap.putInt(RECORDING_ERROR_KEY, error.toInt());
                        returnMap.putString(RECORDING_URL_KEY, null);
                        promise.resolve(returnMap);
                    }

                    @Override
                    public void onSuccess(String url) {
                        WritableMap returnMap = Arguments.createMap();
                        returnMap.putBoolean(RECORDING_SUCCESS_KEY, true);
                        returnMap.putInt(RECORDING_ERROR_KEY, Error.NONE.toInt());
                        returnMap.putString(RECORDING_URL_KEY, url);
                        promise.resolve(returnMap);
                    }
                };

                // Stop recording if we have the right permissions
                checkPermissionsAndRun(new PermissionListener() {
                    @Override
                    public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
                        recorder.stopRecordingAsync(completionCallback);
                        return true;
                    }
                }, true);
            }
        });
    }

    @ReactMethod
    public void takeScreenshot(final int sceneNavTag, final String fileName,
                               final boolean saveToCameraRoll, final Promise promise) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            WritableMap returnMap = Arguments.createMap();
            returnMap.putBoolean(RECORDING_SUCCESS_KEY, false);
            returnMap.putInt(RECORDING_ERROR_KEY, UNSUPPORTED_PLATFORM_ERROR);
            returnMap.putString(RECORDING_URL_KEY, null);
            promise.resolve(returnMap);
            return;
        }
        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View sceneView = viewResolver.resolveView(sceneNavTag);
                if (!(sceneView instanceof VRTARSceneNavigator)) {
                    throw new IllegalViewOperationException("Viro: Attempted to call takeScreenshot on a non-ARSceneNav view!");
                }
                VRTARSceneNavigator scene = (VRTARSceneNavigator) sceneView;
                final ViroViewARCore arView = scene.getARView();

                if (arView == null) {
                    WritableMap returnMap = Arguments.createMap();
                    returnMap.putBoolean(RECORDING_SUCCESS_KEY, false);
                    returnMap.putInt(RECORDING_ERROR_KEY, UNSUPPORTED_PLATFORM_ERROR);
                    returnMap.putString(RECORDING_URL_KEY, null);
                    promise.resolve(returnMap);
                    return;
                }

                // Use PixelCopy-based screenshot which properly captures the camera background
                arView.takeScreenshotWithPixelCopy(new ViroViewARCore.PixelCopyScreenshotListener() {
                    @Override
                    public void onSuccess(Bitmap bitmap) {
                        // Save the bitmap to file
                        String filePath = saveScreenshotToFile(bitmap, fileName, saveToCameraRoll);

                        WritableMap returnMap = Arguments.createMap();
                        if (filePath != null) {
                            returnMap.putBoolean(RECORDING_SUCCESS_KEY, true);
                            returnMap.putInt(RECORDING_ERROR_KEY, Error.NONE.toInt());
                            returnMap.putString(RECORDING_URL_KEY, filePath);
                        } else {
                            returnMap.putBoolean(RECORDING_SUCCESS_KEY, false);
                            returnMap.putInt(RECORDING_ERROR_KEY, Error.WRITE_TO_FILE.toInt());
                            returnMap.putString(RECORDING_URL_KEY, null);
                        }
                        bitmap.recycle();
                        promise.resolve(returnMap);
                    }

                    @Override
                    public void onError(int errorCode) {
                        WritableMap returnMap = Arguments.createMap();
                        returnMap.putBoolean(RECORDING_SUCCESS_KEY, false);
                        returnMap.putInt(RECORDING_ERROR_KEY, Error.UNKNOWN.toInt());
                        returnMap.putString(RECORDING_URL_KEY, null);
                        promise.resolve(returnMap);
                    }
                });
            }
        });
    }

    /**
     * Saves a bitmap to a file and returns the file path.
     */
    private String saveScreenshotToFile(Bitmap bitmap, String fileName, boolean saveToCameraRoll) {
        if (fileName == null || fileName.trim().isEmpty()) {
            return null;
        }

        String dirPath = getMediaStorageDirectory(mContext, saveToCameraRoll);
        if (dirPath == null) {
            return null;
        }

        File dir = new File(dirPath);
        if (!dir.exists() && !dir.mkdirs()) {
            Log.e("Viro", "Failed to create directory: " + dirPath);
            return null;
        }

        File outputFile = new File(dir, fileName + ".jpg");
        BufferedOutputStream bos = null;
        try {
            bos = new BufferedOutputStream(new FileOutputStream(outputFile));
            bitmap.compress(Bitmap.CompressFormat.JPEG, 100, bos);
            bos.flush();
        } catch (IOException e) {
            Log.e("Viro", "Failed to save screenshot: " + e.getMessage());
            return null;
        } finally {
            if (bos != null) {
                try {
                    bos.close();
                } catch (IOException e) {
                    Log.e("Viro", "Failed to close output stream: " + e.getMessage());
                }
            }
        }

        // Notify media scanner if saving to camera roll
        if (saveToCameraRoll) {
            Intent mediaScanIntent = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE);
            Uri contentUri = Uri.fromFile(outputFile);
            mediaScanIntent.setData(contentUri);
            mContext.sendBroadcast(mediaScanIntent);
        }

        return outputFile.getAbsolutePath();
    }

    /**
     * Gets the directory path for saving media files.
     */
    private static String getMediaStorageDirectory(Context context, boolean saveToCameraRoll) {
        ApplicationInfo appInfo = context.getApplicationInfo();
        CharSequence appLabel = context.getPackageManager().getApplicationLabel(appInfo);
        String appName = (appLabel != null && appLabel.length() > 0)
                ? appLabel.toString()
                : context.getPackageName();

        if (saveToCameraRoll) {
            File picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
            if (picturesDir != null) {
                return picturesDir.getAbsolutePath() + "/" + appName;
            }
            File externalDir = Environment.getExternalStorageDirectory();
            if (externalDir != null) {
                return externalDir.getAbsolutePath() + "/" + appName;
            }
            Log.e("Viro", "Unable to access camera roll directory");
            return null;
        } else {
            return context.getFilesDir().getAbsolutePath();
        }
    }

    @ReactMethod
    public void resetARSession(final int sceneNavTag, final boolean resetTracking, final boolean removeAnchors) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            return;
        }
        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View view = viewResolver.resolveView(sceneNavTag);
                if (view instanceof VRTARSceneNavigator) {
                    VRTARSceneNavigator sceneNavigator = (VRTARSceneNavigator) view;
                    sceneNavigator.resetARSession();
                }
            }
        });
    }

    @ReactMethod
    public void setWorldOrigin(final int sceneNavTag, final ReadableMap worldOrigin) {
        // no-op
    }

    @ReactMethod
    public void project(final int sceneNavTag, final ReadableArray point, final Promise promise) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            promise.reject("ERROR", "UIManager not available");
            return;
        }
        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View view = viewResolver.resolveView(sceneNavTag);
                if (view instanceof VRTARSceneNavigator) {
                    VRTARSceneNavigator sceneNavigator = (VRTARSceneNavigator) view;
                    float[] projectPoint = {0,0,0};
                    projectPoint[0] = (float)point.getDouble(0);
                    projectPoint[1] = (float)point.getDouble(1);
                    projectPoint[2] = (float)point.getDouble(2);
                    Vector projectedPoint = sceneNavigator.projectPoint(new Vector(projectPoint[0], projectPoint[1], projectPoint[2]));

                    WritableMap returnMap = Arguments.createMap();
                    WritableArray writablePosArray = Arguments.createArray();
                    writablePosArray.pushDouble(projectedPoint.x);
                    writablePosArray.pushDouble(projectedPoint.y);
                    returnMap.putArray("screenPosition", writablePosArray);
                    promise.resolve(returnMap);
                }
            }
        });
    }

    @ReactMethod
    public void unproject(final int sceneNavTag, final ReadableArray point, final Promise promise) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            promise.reject("ERROR", "UIManager not available");
            return;
        }
        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View view = viewResolver.resolveView(sceneNavTag);
                if (view instanceof VRTARSceneNavigator) {
                    VRTARSceneNavigator sceneNavigator = (VRTARSceneNavigator) view;
                    float[] unprojectPoint = {0,0,0};
                    unprojectPoint[0] = (float)point.getDouble(0);
                    unprojectPoint[1] = (float)point.getDouble(1);
                    unprojectPoint[2] = (float)point.getDouble(2);
                    Vector unProjectedPoint = sceneNavigator.unprojectPoint(new Vector(unprojectPoint[0], unprojectPoint[1], unprojectPoint[2]));

                    WritableMap returnMap = Arguments.createMap();
                    WritableArray writablePosArray = Arguments.createArray();
                    writablePosArray.pushDouble(unProjectedPoint.x);
                    writablePosArray.pushDouble(unProjectedPoint.y);
                    writablePosArray.pushDouble(unProjectedPoint.z);
                    returnMap.putArray("position", writablePosArray);
                    promise.resolve(returnMap);
                }
            }
        });
    }

    @ReactMethod()
    public void isARSupportedOnDevice(final Callback successCallback) {
        ViroViewARCore.ARCoreAvailability availability = ViroViewARCore.isARSupportedOnDevice(getReactApplicationContext());
        successCallback.invoke(availability.toString());
    }

    @ReactMethod
    public void hostCloudAnchor(final int sceneNavTag, final String anchorId,
                                final int ttlDays, final Promise promise) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            WritableMap result = Arguments.createMap();
            result.putBoolean("success", false);
            result.putString("error", "UIManager not available");
            result.putString("state", "ErrorInternal");
            promise.resolve(result);
            return;
        }

        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View view = viewResolver.resolveView(sceneNavTag);
                if (!(view instanceof VRTARSceneNavigator)) {
                    WritableMap result = Arguments.createMap();
                    result.putBoolean("success", false);
                    result.putString("error", "Invalid view type");
                    result.putString("state", "ErrorInternal");
                    promise.resolve(result);
                    return;
                }

                VRTARSceneNavigator sceneNavigator = (VRTARSceneNavigator) view;
                sceneNavigator.hostCloudAnchor(anchorId, ttlDays, new CloudAnchorCallback() {
                    @Override
                    public void onSuccess(String cloudAnchorId) {
                        WritableMap result = Arguments.createMap();
                        result.putBoolean("success", true);
                        result.putString("cloudAnchorId", cloudAnchorId);
                        result.putString("state", "Success");
                        promise.resolve(result);
                    }

                    @Override
                    public void onFailure(String error, String state) {
                        WritableMap result = Arguments.createMap();
                        result.putBoolean("success", false);
                        result.putString("error", error);
                        result.putString("state", state);
                        promise.resolve(result);
                    }
                });
            }
        });
    }

    @ReactMethod
    public void resolveCloudAnchor(final int sceneNavTag, final String cloudAnchorId,
                                   final Promise promise) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            WritableMap result = Arguments.createMap();
            result.putBoolean("success", false);
            result.putString("error", "UIManager not available");
            result.putString("state", "ErrorInternal");
            promise.resolve(result);
            return;
        }

        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View view = viewResolver.resolveView(sceneNavTag);
                if (!(view instanceof VRTARSceneNavigator)) {
                    WritableMap result = Arguments.createMap();
                    result.putBoolean("success", false);
                    result.putString("error", "Invalid view type");
                    result.putString("state", "ErrorInternal");
                    promise.resolve(result);
                    return;
                }

                VRTARSceneNavigator sceneNavigator = (VRTARSceneNavigator) view;
                sceneNavigator.resolveCloudAnchor(cloudAnchorId, new CloudAnchorResolveCallback() {
                    @Override
                    public void onSuccess(WritableMap anchorData) {
                        WritableMap result = Arguments.createMap();
                        result.putBoolean("success", true);
                        result.putMap("anchor", anchorData);
                        result.putString("state", "Success");
                        promise.resolve(result);
                    }

                    @Override
                    public void onFailure(String error, String state) {
                        WritableMap result = Arguments.createMap();
                        result.putBoolean("success", false);
                        result.putString("error", error);
                        result.putString("state", state);
                        promise.resolve(result);
                    }
                });
            }
        });
    }

    @ReactMethod
    public void cancelCloudAnchorOperations(final int sceneNavTag) {
        UIManager uiManager = UIManagerHelper.getUIManager(getReactApplicationContext(), sceneNavTag);
        if (uiManager == null) {
            return;
        }

        ((FabricUIManager) uiManager).addUIBlock(new com.facebook.react.fabric.interop.UIBlock() {
            @Override
            public void execute(com.facebook.react.fabric.interop.UIBlockViewResolver viewResolver) {
                View view = viewResolver.resolveView(sceneNavTag);
                if (view instanceof VRTARSceneNavigator) {
                    VRTARSceneNavigator sceneNavigator = (VRTARSceneNavigator) view;
                    sceneNavigator.cancelCloudAnchorOperations();
                }
            }
        });
    }

    /**
     * Callback interface for cloud anchor hosting operations.
     */
    public interface CloudAnchorCallback {
        void onSuccess(String cloudAnchorId);
        void onFailure(String error, String state);
    }

    /**
     * Callback interface for cloud anchor resolve operations.
     */
    public interface CloudAnchorResolveCallback {
        void onSuccess(WritableMap anchorData);
        void onFailure(String error, String state);
    }

    private void checkPermissionsAndRun(PermissionListener listener, boolean audioAndRecordingPerm){
        Activity activity = mContext.getCurrentActivity();

        // return if we already have permissions
        if (audioAndRecordingPerm && hasAudioAndRecordingPermissions(mContext)) {
            listener.onRequestPermissionsResult(0, null, null);
            return;
        } else if (!audioAndRecordingPerm && hasRecordingPermissions(mContext)) {
            listener.onRequestPermissionsResult(0, null, null);
            return;
        }

        if (!(activity instanceof ReactActivity)){
            Log.e("Viro","Error: Missing ReactActivity required for checking recording permissions!");

            // Trigger a permission failure callback.
            listener.onRequestPermissionsResult(0, null, null);
            return;
        }

        ReactActivity reactActivity = (ReactActivity) activity;
        if (audioAndRecordingPerm){
            reactActivity.requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    Manifest.permission.RECORD_AUDIO}, PERMISSION_REQ_CODE_AUDIO, listener);
        } else {
            reactActivity.requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE},
                    PERMISSION_REQ_CODE_STORAGE, listener);
        }
    }

    private static boolean hasAudioAndRecordingPermissions(Context context) {
        boolean hasRecordPermissions = ContextCompat.checkSelfPermission(context, "android.permission.RECORD_AUDIO") == 0;
        boolean hasExternalStoragePerm = ContextCompat.checkSelfPermission(context, "android.permission.WRITE_EXTERNAL_STORAGE") == 0;
        return hasRecordPermissions && hasExternalStoragePerm;
    }

    private static boolean hasRecordingPermissions(Context context) {
        return ContextCompat.checkSelfPermission(context, "android.permission.WRITE_EXTERNAL_STORAGE") == 0;
    }
}
