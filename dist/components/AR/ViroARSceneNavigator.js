/**
 * Copyright (c) 2017-present, Viro Media, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 * @providesModule ViroARSceneNavigator
 * @flow
 */
"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.ViroARSceneNavigator = exports.SCAN_WAVE_PRESETS = void 0;
const React = __importStar(require("react"));
const react_native_1 = require("react-native");
const ViroARSceneNavigatorModule = react_native_1.NativeModules.VRTARSceneNavigatorModule;
let mathRandomOffset = 0;
/** Pre-built scan wave configurations. */
exports.SCAN_WAVE_PRESETS = {
    /** Default — luminous cool pearl white (Vision Pro style). Native defaults ARE this preset. */
    visionProCoolPearl: {},
    /** Warm pearl — same structure, warm-shifted palette */
    visionProWarmPearl: {
        waveCoreColor: [1.0, 0.97, 0.92],
        waveHaloColor: [1.0, 0.93, 0.85],
        rimColor: [1.0, 0.9, 0.8],
        noiseTint: [1.0, 0.95, 0.9],
    },
    /** Minimal — reduced intensities for subtlety */
    subtleMinimal: {
        coreIntensity: 0.5,
        haloIntensity: 0.15,
        rimIntensity: 0.3,
        noiseIntensity: 0.05,
        duration: 800,
    },
};
/**
 * ViroARSceneNavigator is used to transition between multiple AR Scenes.
 * Internal class component - use ViroARSceneNavigator (the forwardRef wrapper) for ref access.
 */
class ViroARSceneNavigatorClass extends React.Component {
    _component = null;
    constructor(props) {
        super(props);
        let initialSceneTag = this.props.initialSceneKey;
        if (initialSceneTag == null) {
            initialSceneTag = this.getRandomTag();
        }
        const scene = {
            sceneClass: this.props.initialScene,
            tag: initialSceneTag,
            referenceCount: 1,
        };
        const sceneDict = {};
        sceneDict[scene.tag] = scene;
        this.state = {
            sceneDictionary: sceneDict,
            sceneHistory: [scene.tag],
            currentSceneIndex: 0,
        };
    }
    componentWillUnmount() {
        // Explicitly trigger native cleanup to prevent memory leaks
        // This ensures ARSession is properly paused and GL resources are released
        const nodeHandle = (0, react_native_1.findNodeHandle)(this);
        if (nodeHandle) {
            ViroARSceneNavigatorModule.cleanup(nodeHandle);
        }
    }
    /**
     * Starts recording video of the Viro renderer and external audio
     *
     * @param fileName - name of the file (without extension)
     * @param saveToCameraRoll - whether or not the file should also be saved to the camera roll
     * @param onError - callback function that accepts an errorCode.
     */
    _startVideoRecording = (fileName, saveToCameraRoll, 
    // TODO: What are the errorCodes? make a type for this
    onError) => {
        ViroARSceneNavigatorModule.startVideoRecording((0, react_native_1.findNodeHandle)(this), fileName, saveToCameraRoll, onError);
    };
    /**
     * Stops recording the video of the Viro Renderer.
     *
     * returns Object w/ success, url and errorCode keys.
     * @returns Promise that resolves when the video has stopped recording.
     */
    _stopVideoRecording = async () => {
        return await ViroARSceneNavigatorModule.stopVideoRecording((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Takes a screenshot of the Viro renderer
     *
     * @param fileName - name of the file (without extension)
     * @param saveToCameraRoll - whether or not the file should also be saved to the camera roll
     * returns Object w/ success, url and errorCode keys.
     */
    _takeScreenshot = async (fileName, saveToCameraRoll) => {
        return await ViroARSceneNavigatorModule.takeScreenshot((0, react_native_1.findNodeHandle)(this), fileName, saveToCameraRoll);
    };
    /**
     * Takes a high-resolution photo using ARKit's captureHighResolutionFrame (iOS 16+).
     * This captures the camera image at full sensor resolution (up to 12MP) with
     * the 3D scene composited on top.
     *
     * @param fileName - name of the file (without extension)
     * @param saveToCameraRoll - whether or not the file should also be saved to the camera roll
     * @returns Object with success, url, and errorCode keys.
     *          errorCode: 0=success, 1=no permissions, 5=write failed,
     *                     10=iOS<16 not supported, 11=capture failed, 15=session not ready
     */
    _takeHighResolutionPhoto = async (fileName, saveToCameraRoll) => {
        return await ViroARSceneNavigatorModule.takeHighResolutionPhoto((0, react_native_1.findNodeHandle)(this), fileName, saveToCameraRoll);
    };
    /**
     * @todo document _project
     *
     * @param point
     * @returns
     */
    _project = async (point) => {
        return await ViroARSceneNavigatorModule.project((0, react_native_1.findNodeHandle)(this), point);
    };
    /**
     * TODO: Document _unproject
     *
     * @param point
     * @returns
     */
    _unproject = async (point) => {
        return await ViroARSceneNavigatorModule.unproject((0, react_native_1.findNodeHandle)(this), point);
    };
    /**
     * Gets a random tag string.
     *
     * @returns a random tag.
     */
    getRandomTag = () => {
        const randomTag = Math.random() + mathRandomOffset;
        mathRandomOffset++;
        return randomTag.toString();
    };
    /**
     * Pushes a scene and reference it with the given key if provided.
     * If the scene has been previously pushed, we simply show the scene again.
     * Note that the back history order of which scenes were pushed is preserved.
     * Also note that scenes are reference counted and only a unique set of
     * scenes are stored and mapped to within sceneDictionary.
     *
     * Can take in either 1 or two parameters in the form:
     * push ("sceneKey");
     * push ("sceneKey", scene);
     * push (scene);
     *
     * @todo use Typescript function overloading rather than this inaccurate solution
     * @todo document parameters
     */
    push = (param1, param2) => {
        let sceneKey = undefined;
        let scene = undefined;
        if (typeof param1 == "string") {
            sceneKey = param1;
            scene = param2;
        }
        else {
            scene = param1;
        }
        if (scene == undefined && sceneKey == undefined) {
            console.log("ERROR: pushing requires either the scene tag, or both the tag and scene.");
            return;
        }
        else if (scene == undefined &&
            sceneKey != undefined &&
            !(sceneKey in this.state.sceneDictionary)) {
            console.log("ERROR: Cannot push with a new sceneKey with no associated scene.");
            return;
        }
        if (sceneKey == undefined ||
            (typeof sceneKey == "string" && sceneKey.trim().length <= 0)) {
            sceneKey = this.getRandomTag();
        }
        this.incrementSceneReference(scene, sceneKey, false);
        this.addToHistory(sceneKey);
    };
    /**
     * Replace the top scene in the stack with the given scene. The remainder of the back
     * history is kept in the same order as before.
     *
     * Can take in either 1 or two parameters in the form:
     * replace ("sceneKey");
     * replace ("sceneKey", scene);
     * replace (scene);
     *
     * @todo use Typescript function overloading rather than this inaccurate solution
     * @todo document parameters
     */
    replace = (param1, param2) => {
        let sceneKey = undefined;
        let scene = undefined;
        if (typeof param1 == "string") {
            sceneKey = param1;
            scene = param2;
        }
        else {
            scene = param1;
        }
        if (scene == undefined && sceneKey == undefined) {
            console.log("ERROR: replacing requires either the scene tag, or both the tag and scene.");
            return;
        }
        else if (scene == undefined &&
            sceneKey != undefined &&
            !(sceneKey in this.state.sceneDictionary)) {
            console.log("ERROR: Cannot replace with a new sceneKey with no associated scene.");
            return;
        }
        if (sceneKey == undefined ||
            (typeof sceneKey == "string" && sceneKey.trim().length <= 0)) {
            sceneKey = this.getRandomTag();
        }
        // Pop 1 off the scene history (do not use popN because in this case we allow
        // popping the root), then push this scene
        this.decrementReferenceForLastNScenes(1);
        this.popHistoryByN(1);
        this.incrementSceneReference(scene, sceneKey, false);
        this.addToHistory(sceneKey);
    };
    /**
     * Jumps to a given scene that had been previously pushed. If the scene was not pushed, we
     * then push and jump to it. The back history is re-ordered such that jumped to scenes are
     * re-ordered to the front. As such, only the back order of sequential jumps are preserved.
     *
     * Can take in either 1 or two parameters in the form:
     * jump ("sceneKey");
     * jump ("sceneKey", scene);
     * jump (scene);
     *
     * @todo use Typescript function overloading rather than this inaccurate solution
     * @todo document parameters
     */
    jump = (param1, param2) => {
        let sceneKey = undefined;
        let scene = undefined;
        if (typeof param1 == "string") {
            sceneKey = param1;
            scene = param2;
        }
        else {
            scene = param1;
        }
        if (scene == undefined && sceneKey == undefined) {
            console.log("ERROR: jumping requires either the scene tag, or both the tag and scene.");
            return;
        }
        else if (scene == undefined &&
            sceneKey != undefined &&
            !(sceneKey in this.state.sceneDictionary)) {
            console.log("ERROR: Cannot jump with a new sceneKey with no associated scene.");
            return;
        }
        if (sceneKey == undefined ||
            (typeof sceneKey == "string" && sceneKey.trim().length <= 0)) {
            sceneKey = this.getRandomTag();
        }
        this.incrementSceneReference(scene, sceneKey, true);
        this.reorderHistory(sceneKey);
    };
    /**
     * Pop 1 screen from the stack.
     */
    pop = () => {
        this.popN(1);
    };
    /**
     * Pop n screens from the stack.
     *
     * @param n number of scenes to pop
     * @returns void
     */
    popN = (n) => {
        if (n === 0) {
            return;
        }
        if (this.state.sceneHistory.length - n <= 0) {
            console.log("WARN: Attempted to pop the root scene in ViroARSceneNavigator!");
            return;
        }
        this.decrementReferenceForLastNScenes(n);
        this.popHistoryByN(n);
    };
    /**
     * Increments the reference count for a scene within sceneDictionary that is
     * mapped to the given sceneKey. If no scenes are found / mapped, we create
     * one, initialize it with a reference count of 1, and store it within the
     * sceneDictionary for future reference.
     *
     * @todo TODO: Document parameters.
     */
    incrementSceneReference = (scene, sceneKey, limitOne) => {
        const currentSceneDictionary = this.state.sceneDictionary;
        if (!(sceneKey in currentSceneDictionary)) {
            const newScene = {
                sceneClass: scene,
                tag: sceneKey,
                referenceCount: 0,
            };
            currentSceneDictionary[sceneKey] = newScene;
        }
        // Error out if there are no scenes matching the given sceneKey
        const currentScene = currentSceneDictionary[sceneKey];
        if (currentScene == null || currentScene == undefined) {
            console.log("ERROR: No scene found for: " + sceneKey);
            return;
        }
        // Update the scene's reference count and then the sceneDictionary
        if ((limitOne && currentScene.referenceCount < 1) || !limitOne) {
            currentScene.referenceCount++;
        }
        currentSceneDictionary[sceneKey] = currentScene;
        // Finally update all states
        this.setState({
            sceneDictionary: currentSceneDictionary,
        });
    };
    /**
     * Decrements the reference count for the last N scenes within
     * the sceneHistory by 1. If nothing else references that given scene
     * (counts equals 0), we then remove that scene from sceneDictionary.
     *
     * @param n number to decrement by.
     */
    decrementReferenceForLastNScenes = (n) => {
        const { sceneHistory, sceneDictionary } = this.state;
        // Now update and release any reference counts
        for (let i = 1; i <= n; i++) {
            const sceneTag = sceneHistory[sceneHistory.length - i];
            const scene = sceneDictionary[sceneTag];
            scene.referenceCount--;
            if (scene.referenceCount <= 0) {
                delete sceneDictionary[sceneTag];
            }
            else {
                sceneDictionary[sceneTag] = scene;
            }
        }
        // Finally update all states
        this.setState({
            sceneDictionary: sceneDictionary,
        });
    };
    /**
     * Adds the given sceneKey to the sceneHistory and updates the currentSceneIndex to point
     * to the scene on the top of the history stack (the most recent scene).
     *
     * @param sceneKey scene to insert into the stack.
     */
    addToHistory = (sceneKey) => {
        const updatedHistory = this.state.sceneHistory.concat([sceneKey]);
        const currentIndex = this.getSceneIndex(sceneKey);
        this.setState({
            currentSceneIndex: currentIndex,
            sceneHistory: updatedHistory,
        });
    };
    /**
     * Instead of preserving history, we find the last pushed sceneKey within the history stack
     * matching the given sceneKey and re-order it to the front. We then update the
     * currentSceneIndex to point to the scene on the top of the history stack
     * (the most recent scene).
     *
     * @param sceneKey scene to put at the top of the stack.
     */
    reorderHistory = (sceneKey) => {
        // Find the last sceneKey within sceneHistory and remove it.
        const { sceneHistory } = this.state;
        for (let i = sceneHistory.length - 1; i >= 0; i--) {
            if (sceneKey == sceneHistory[i]) {
                sceneHistory.splice(i, 1);
                break;
            }
        }
        // Add back the sceneKey to the front of the History stack.
        const updatedHistory = sceneHistory.concat([sceneKey]);
        const currentIndex = this.getSceneIndex(sceneKey);
        this.setState({
            currentSceneIndex: currentIndex,
            sceneHistory: updatedHistory,
        });
    };
    /**
     * Pops the history entries by n screens.
     *
     * @param n number of history entries to pop.
     */
    popHistoryByN(n) {
        const { sceneHistory } = this.state;
        sceneHistory.splice(sceneHistory.length - n, n);
        const currentIndex = this.getSceneIndex(sceneHistory[sceneHistory.length - 1]);
        // Finally update all states
        this.setState({
            currentSceneIndex: currentIndex,
            sceneHistory: sceneHistory,
        });
    }
    /**
     * Gets the index of a scene by the scene tag.
     *
     * @param sceneTag tag of the scene
     * @returns the index of the scene
     */
    getSceneIndex = (sceneTag) => {
        const { sceneDictionary } = this.state;
        let i = 0;
        for (const sceneKey in sceneDictionary) {
            if (sceneTag == sceneDictionary[sceneKey].tag) {
                return i;
            }
            i++;
        }
        // Unable to find the given sceneTag, return -1
        return -1;
    };
    /**
     * [iOS Only]
     *
     * Resets the tracking of the AR session.
     *
     * @param resetTracking - determines if the tracking should be reset.
     * @param removeAnchors - determines if the existing anchors should be removed too.
     */
    /**
     * [iOS Only]
     *
     * Checks if the native ARSession is available and accessible.
     * Useful for verifying if the AR session has been successfully initialized
     * and exposed to the React Native bridge.
     *
     * @returns Promise resolving to a boolean indicating availability
     */
    _isNativeARSessionAvailable = async () => {
        return await ViroARSceneNavigatorModule.isNativeARSessionAvailable((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * [iOS Only]
     *
     * Resets the tracking of the AR session.
     *
     * @param resetTracking - determines if the tracking should be reset.
     * @param removeAnchors - determines if the existing anchors should be removed too.
     */
    _resetARSession = (resetTracking, removeAnchors) => {
        ViroARSceneNavigatorModule.resetARSession((0, react_native_1.findNodeHandle)(this), resetTracking, removeAnchors);
    };
    /**
     * [iOS/ARKit 1.5+ Only]
     *
     * Allows the developer to offset the current world orgin
     * by the given transformation matrix. ie. if this is called twice with the
     * position [0, 0, 1], then current world origin will be at [0, 0, 2] from its
     * initial position (it's additive, not meant to replace the existing origin)
     *
     * @param worldOrigin - a dictionary that can contain a `position` and `rotation` key with an
     *  array containing 3 floats (note: rotation is in degrees).
     */
    _setWorldOrigin = (worldOrigin) => {
        ViroARSceneNavigatorModule.setWorldOrigin((0, react_native_1.findNodeHandle)(this), worldOrigin);
    };
    /**
     * Host a local anchor to the cloud for cross-platform sharing.
     *
     * The anchor must already exist in the AR session (e.g., created from a hit test
     * or plane detection). Once hosted, the returned cloudAnchorId can be shared
     * with other devices to resolve the same anchor.
     *
     * @param anchorId - The local anchor ID to host (from ViroAnchor.anchorId)
     * @param ttlDays - Time-to-live in days (1-365). Default: 1 day.
     *                  Note: TTL > 1 requires keyless authorization on Google Cloud.
     * @returns Promise resolving to the hosting result with cloudAnchorId
     */
    _hostCloudAnchor = async (anchorId, ttlDays = 1) => {
        return await ViroARSceneNavigatorModule.hostCloudAnchor((0, react_native_1.findNodeHandle)(this), anchorId, Math.max(1, Math.min(365, ttlDays)) // Clamp to valid range
        );
    };
    /**
     * Resolve a cloud anchor by its ID.
     *
     * Once resolved, the anchor will be added to the AR session and can be used
     * to place virtual content at the same real-world location as the original
     * hosted anchor (even on a different device).
     *
     * @param cloudAnchorId - The cloud anchor ID to resolve (from hostCloudAnchor result)
     * @returns Promise resolving to the anchor data
     */
    _resolveCloudAnchor = async (cloudAnchorId) => {
        return await ViroARSceneNavigatorModule.resolveCloudAnchor((0, react_native_1.findNodeHandle)(this), cloudAnchorId);
    };
    /**
     * Cancel all pending cloud anchor operations.
     * Use this when exiting a scene or when cloud operations are no longer needed.
     */
    _cancelCloudAnchorOperations = () => {
        ViroARSceneNavigatorModule.cancelCloudAnchorOperations((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Create an AR anchor at the specified world position.
     *
     * The anchor can later be used with hostCloudAnchor() to persist it to the cloud
     * for cross-device sharing. The returned anchorId is compatible with the
     * anchorId parameter expected by hostCloudAnchor().
     *
     * @param position - World position [x, y, z] where the anchor should be created
     * @returns Promise resolving to the creation result with anchorId
     */
    _addAnchor = async (position) => {
        return await ViroARSceneNavigatorModule.addAnchor((0, react_native_1.findNodeHandle)(this), position);
    };
    /**
     * Create an AR anchor at the specified world position and immediately host it to the cloud.
     * This is an atomic operation that creates a native ARKit anchor and hosts it in one step,
     * avoiding lookup issues that can occur when creating and hosting anchors separately.
     *
     * @param position - World position [x, y, z] in meters
     * @param ttlDays - Time-to-live in days for the cloud anchor (1-365)
     * @returns Promise resolving to the cloud hosting result with cloudAnchorId
     */
    _createAndHostCloudAnchor = async (position, ttlDays) => {
        return await ViroARSceneNavigatorModule.createAndHostCloudAnchor((0, react_native_1.findNodeHandle)(this), position, ttlDays);
    };
    // ===========================================================================
    // Geospatial API Methods
    // ===========================================================================
    /**
     * Check if geospatial mode is supported on this device.
     *
     * @returns Promise resolving to support status
     */
    _isGeospatialModeSupported = async () => {
        return await ViroARSceneNavigatorModule.isGeospatialModeSupported((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Enable or disable geospatial mode.
     * When enabled, the session will track the device's position relative to the Earth.
     *
     * @param enabled - Whether to enable geospatial mode
     */
    _setGeospatialModeEnabled = (enabled) => {
        ViroARSceneNavigatorModule.setGeospatialModeEnabled((0, react_native_1.findNodeHandle)(this), enabled);
    };
    /**
     * Get the current Earth tracking state.
     *
     * @returns Promise resolving to the current tracking state
     */
    _getEarthTrackingState = async () => {
        return await ViroARSceneNavigatorModule.getEarthTrackingState((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Get the camera's current geospatial pose (latitude, longitude, altitude, etc.)
     *
     * @returns Promise resolving to the camera's geospatial pose
     */
    _getCameraGeospatialPose = async () => {
        return await ViroARSceneNavigatorModule.getCameraGeospatialPose((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Check VPS (Visual Positioning System) availability at a specific location.
     * VPS provides enhanced accuracy in supported locations.
     *
     * @param latitude - Latitude in degrees
     * @param longitude - Longitude in degrees
     * @returns Promise resolving to VPS availability status
     */
    _checkVPSAvailability = async (latitude, longitude) => {
        return await ViroARSceneNavigatorModule.checkVPSAvailability((0, react_native_1.findNodeHandle)(this), latitude, longitude);
    };
    /**
     * Create a WGS84 geospatial anchor at the specified location.
     * The anchor is positioned using absolute coordinates on the WGS84 ellipsoid.
     *
     * @param latitude - Latitude in degrees
     * @param longitude - Longitude in degrees
     * @param altitude - Altitude in meters above the WGS84 ellipsoid
     * @param quaternion - Orientation quaternion [x, y, z, w] in EUS frame (optional, defaults to facing north)
     * @returns Promise resolving to the created anchor
     */
    _createGeospatialAnchor = async (latitude, longitude, altitude, quaternion) => {
        return await ViroARSceneNavigatorModule.createGeospatialAnchor((0, react_native_1.findNodeHandle)(this), latitude, longitude, altitude, quaternion || [0, 0, 0, 1]);
    };
    /**
     * Create a terrain anchor at the specified location.
     * The anchor is positioned relative to the terrain surface.
     *
     * @param latitude - Latitude in degrees
     * @param longitude - Longitude in degrees
     * @param altitudeAboveTerrain - Altitude in meters above terrain
     * @param quaternion - Orientation quaternion [x, y, z, w] in EUS frame (optional)
     * @returns Promise resolving to the created anchor
     */
    _createTerrainAnchor = async (latitude, longitude, altitudeAboveTerrain, quaternion) => {
        return await ViroARSceneNavigatorModule.createTerrainAnchor((0, react_native_1.findNodeHandle)(this), latitude, longitude, altitudeAboveTerrain, quaternion || [0, 0, 0, 1]);
    };
    /**
     * Create a rooftop anchor at the specified location.
     * The anchor is positioned relative to a building rooftop.
     *
     * @param latitude - Latitude in degrees
     * @param longitude - Longitude in degrees
     * @param altitudeAboveRooftop - Altitude in meters above rooftop
     * @param quaternion - Orientation quaternion [x, y, z, w] in EUS frame (optional)
     * @returns Promise resolving to the created anchor
     */
    _createRooftopAnchor = async (latitude, longitude, altitudeAboveRooftop, quaternion) => {
        return await ViroARSceneNavigatorModule.createRooftopAnchor((0, react_native_1.findNodeHandle)(this), latitude, longitude, altitudeAboveRooftop, quaternion || [0, 0, 0, 1]);
    };
    /**
     * Remove a geospatial anchor from the session.
     *
     * @param anchorId - The ID of the anchor to remove
     */
    _removeGeospatialAnchor = (anchorId) => {
        ViroARSceneNavigatorModule.removeGeospatialAnchor((0, react_native_1.findNodeHandle)(this), anchorId);
    };
    // ===========================================================================
    // Scene Semantics API Methods
    // ===========================================================================
    /**
     * Check if Scene Semantics mode is supported on this device.
     * Scene Semantics uses ML to classify each pixel in the camera feed
     * into categories like sky, building, tree, road, etc.
     *
     * @returns Promise resolving to support status
     */
    _isSemanticModeSupported = async () => {
        return await ViroARSceneNavigatorModule.isSemanticModeSupported((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Enable or disable Scene Semantics mode.
     * When enabled, the session will process each frame to generate
     * semantic labels for each pixel.
     *
     * @param enabled - Whether to enable semantic mode
     */
    _setSemanticModeEnabled = (enabled) => {
        ViroARSceneNavigatorModule.setSemanticModeEnabled((0, react_native_1.findNodeHandle)(this), enabled);
    };
    /**
     * Get the fraction of pixels for each semantic label in the current frame.
     * Returns a dictionary with label names as keys and fractions (0.0-1.0) as values.
     *
     * Available labels: unlabeled, sky, building, tree, road, sidewalk,
     * terrain, structure, object, vehicle, person, water
     *
     * @returns Promise resolving to semantic label fractions
     */
    _getSemanticLabelFractions = async () => {
        return await ViroARSceneNavigatorModule.getSemanticLabelFractions((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Get the fraction of pixels for a specific semantic label.
     *
     * @param label - The semantic label name (e.g., "sky", "building", "road")
     * @returns Promise resolving to the fraction of pixels with that label
     */
    _getSemanticLabelFraction = async (label) => {
        return await ViroARSceneNavigatorModule.getSemanticLabelFraction((0, react_native_1.findNodeHandle)(this), label);
    };
    // ===========================================================================
    // Monocular Depth Estimation API Methods
    // ===========================================================================
    /**
     * Check if monocular depth estimation is supported on this device.
     * Requires iOS 14.0+ with Neural Engine capabilities.
     *
     * @returns Promise resolving to support status
     */
    _isMonocularDepthSupported = async () => {
        return await ViroARSceneNavigatorModule.isMonocularDepthSupported((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Check if the monocular depth model has been downloaded.
     *
     * @returns Promise resolving to download status
     */
    _isMonocularDepthModelDownloaded = async () => {
        return await ViroARSceneNavigatorModule.isMonocularDepthModelDownloaded((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Enable or disable monocular depth estimation.
     * When enabled, depth will be estimated from the camera image using a neural network.
     * This provides depth-based occlusion on devices without LiDAR.
     *
     * Note: The model must be downloaded first using downloadMonocularDepthModel().
     *
     * @param enabled - Whether to enable monocular depth estimation
     */
    _setMonocularDepthEnabled = (enabled) => {
        ViroARSceneNavigatorModule.setMonocularDepthEnabled((0, react_native_1.findNodeHandle)(this), enabled);
    };
    /**
     * Set the base URL for downloading the monocular depth model.
     * The full URL will be: baseURL/DepthPro.mlmodelc.zip
     *
     * @param baseURL - The base URL where the model is hosted
     */
    _setMonocularDepthModelURL = (baseURL) => {
        ViroARSceneNavigatorModule.setMonocularDepthModelURL((0, react_native_1.findNodeHandle)(this), baseURL);
    };
    /**
     * Download the monocular depth model if not already downloaded.
     * This is an asynchronous operation that downloads ~200MB.
     *
     * @returns Promise resolving to download result
     */
    _downloadMonocularDepthModel = async () => {
        return await ViroARSceneNavigatorModule.downloadMonocularDepthModel((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Set whether to prefer monocular depth estimation over LiDAR.
     * When enabled, monocular depth will be used even on devices with LiDAR.
     * Useful for:
     * - Consistency across device types
     * - Testing/comparison purposes
     * - Getting depth estimates beyond LiDAR's ~5m range
     *
     * @param prefer - Whether to prefer monocular depth over LiDAR
     */
    _setPreferMonocularDepth = (prefer) => {
        ViroARSceneNavigatorModule.setPreferMonocularDepth((0, react_native_1.findNodeHandle)(this), prefer);
    };
    /**
     * Check if monocular depth is preferred over LiDAR.
     *
     * @returns Promise resolving to preference status
     */
    _isPreferMonocularDepth = async () => {
        return await ViroARSceneNavigatorModule.isPreferMonocularDepth((0, react_native_1.findNodeHandle)(this));
    };
    // ===========================================================================
    // World Map Persistence API Methods (iOS Only)
    // ===========================================================================
    /**
     * [iOS Only] Manually trigger a world map save.
     * Use this to ensure the world map is saved before navigating away,
     * or when you want to save at a specific point in time.
     *
     * @param sessionId - Unique identifier for the session (used as filename if filePath not provided)
     * @param filePath - Optional custom path to save the world map
     * @returns Promise resolving to the save result with success/error/code and filePath
     */
    _saveWorldMap = async (sessionId, filePath) => {
        return await ViroARSceneNavigatorModule.saveWorldMap((0, react_native_1.findNodeHandle)(this), sessionId, filePath ?? null);
    };
    /**
     * [iOS Only] Load a previously saved world map and restart the AR session.
     *
     * Note: success=true means the session was restarted with initialWorldMap set.
     * Relocalization happens asynchronously - monitor trackingState for .normal.
     *
     * @param sessionId - Unique identifier for the session to load
     * @param filePath - Optional custom path to load from (e.g., downloaded from cloud)
     * @returns Promise resolving to the load result with success/error/code
     */
    _loadWorldMap = async (sessionId, filePath) => {
        return await ViroARSceneNavigatorModule.loadWorldMap((0, react_native_1.findNodeHandle)(this), sessionId, filePath ?? null);
    };
    /**
     * [iOS Only] Delete a previously saved world map from storage.
     *
     * @param sessionId - Unique identifier for the session to delete
     * @returns Promise resolving to the delete result with success/error/code
     */
    _deleteWorldMap = async (sessionId) => {
        return await ViroARSceneNavigatorModule.deleteWorldMap((0, react_native_1.findNodeHandle)(this), sessionId);
    };
    /**
     * [iOS Only] Get the current world mapping status.
     * Use this to check if the world map is ready to save, or to show
     * scanning progress UI.
     *
     * For continuous updates, use the onWorldMappingStatusChanged prop instead.
     *
     * @returns Promise resolving to current mapping status, tracking state, and canSave flag
     */
    _getWorldMappingStatus = async () => {
        return await ViroARSceneNavigatorModule.getWorldMappingStatus((0, react_native_1.findNodeHandle)(this));
    };
    // ===========================================================================
    // Frame Streaming API Methods (for Gemini Vision integration)
    // ===========================================================================
    /**
     * [iOS Only] Start streaming AR frames for external processing (e.g., Gemini Vision).
     *
     * Frames are captured at a configurable rate, JPEG-encoded to exact target dimensions
     * using scale+crop (cover), and delivered via the onFrameUpdate callback.
     *
     * Each frame includes:
     * - frameId: Unique identifier for later 2D→3D resolution
     * - imageData: Base64 JPEG
     * - intrinsics: Camera intrinsics mapped to JPEG dimensions (with crop offsets)
     * - cameraToWorld: Camera pose at capture time
     * - jpegToARTransform: Transform from JPEG UV to AR image UV
     *
     * @param config - Frame streaming configuration
     * @platform ios
     */
    _startFrameStream = (config) => {
        ViroARSceneNavigatorModule.startFrameStream((0, react_native_1.findNodeHandle)(this), config);
    };
    /**
     * [iOS Only] Stop streaming AR frames.
     *
     * @platform ios
     */
    _stopFrameStream = () => {
        ViroARSceneNavigatorModule.stopFrameStream((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * [iOS Only] Resolve 2D detection points to 3D world coordinates.
     *
     * This uses capture-time data stored in the ring buffer, ensuring correct
     * mapping even when the camera has moved since the frame was captured.
     * This is critical for delayed responses from vision AI services like Gemini.
     *
     * Resolution uses a fallback ladder (in order of preference):
     * 1. LiDAR depth sampling (0.95 confidence) - most accurate on Pro devices
     * 2. Raycast vs plane geometry (0.95) - hits actual mesh
     * 3. Raycast vs plane extent (0.85) - hits bounding box
     * 4. Raycast vs estimated planes (0.6) - can shift over time
     * 5. Point cloud fallback (0.3-0.6) - finds nearest feature point to ray
     *
     * @param frameId - The frameId from a ViroFrameEvent
     * @param points - Array of normalized UV coordinates (0-1) in JPEG space
     * @returns Promise resolving to resolution results
     * @platform ios
     */
    _resolveDetections = async (frameId, points) => {
        return await ViroARSceneNavigatorModule.resolveDetections((0, react_native_1.findNodeHandle)(this), frameId, points);
    };
    // ===========================================================================
    // Camera Zoom API Methods
    // ===========================================================================
    /**
     * Set zoom using UIView transform (CGAffineTransform scale).
     * This scales the entire ARView visually, different from camera optical zoom.
     * Useful for quick visual zoom without camera hardware changes.
     *
     * @param zoomFactor - The scale factor (1.0 = normal, 2.0 = 2x scale, etc.)
     * @platform ios
     */
    _setViewZoom = (zoomFactor) => {
        ViroARSceneNavigatorModule.setViewZoom((0, react_native_1.findNodeHandle)(this), zoomFactor);
    };
    // ===========================================================================
    // Render Zoom API Methods (Projection-Based)
    // ===========================================================================
    /**
     * Set render zoom using projection matrix scaling.
     * This modifies the camera's field of view and background texture to achieve
     * a real zoom effect that IS captured in screenshots, video recordings, and photos.
     *
     * Unlike setViewZoom (which uses UI scaling and isn't captured), setRenderZoom
     * modifies the actual render pipeline:
     * - Scales the projection matrix to narrow the field of view
     * - Crops the camera background texture to match
     * - Adjusts hit testing to account for the zoomed viewport
     *
     * @param zoomFactor - The zoom factor (1.0 = no zoom, 2.0 = 2x zoom, etc.)
     *                     Clamped to range [1.0, maxRenderZoom]
     * @platform ios
     */
    _setRenderZoom = (zoomFactor) => {
        ViroARSceneNavigatorModule.setRenderZoom((0, react_native_1.findNodeHandle)(this), zoomFactor);
    };
    /**
     * Get the current render zoom factor.
     *
     * @returns Promise resolving to the current zoom factor
     * @platform ios
     */
    _getRenderZoom = async () => {
        return await ViroARSceneNavigatorModule.getRenderZoom((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Get the maximum render zoom factor.
     *
     * @returns Promise resolving to the maximum zoom factor
     * @platform ios
     */
    _getMaxRenderZoom = async () => {
        return await ViroARSceneNavigatorModule.getMaxRenderZoom((0, react_native_1.findNodeHandle)(this));
    };
    /**
     * Set the maximum render zoom factor.
     *
     * @param maxZoom - The maximum zoom factor (must be >= 1.0)
     * @platform ios
     */
    _setMaxRenderZoom = (maxZoom) => {
        ViroARSceneNavigatorModule.setMaxRenderZoom((0, react_native_1.findNodeHandle)(this), maxZoom);
    };
    /**
     * Renders the Scene Views in the stack.
     *
     * @returns Array of rendered Scene views.
     */
    _renderSceneStackItems = () => {
        let views = [];
        let i = 0;
        const { sceneDictionary } = this.state;
        for (const scene in sceneDictionary) {
            const Component = sceneDictionary[scene].sceneClass.scene;
            const props = sceneDictionary[scene].sceneClass.passProps;
            views.push(<Component key={"scene" + i} sceneNavigator={this.sceneNavigator} {...props} arSceneNavigator={this.arSceneNavigator} {...props}/>);
            i++;
        }
        return views;
    };
    arSceneNavigator = {
        push: this.push,
        pop: this.pop,
        popN: this.popN,
        jump: this.jump,
        replace: this.replace,
        startVideoRecording: this._startVideoRecording,
        stopVideoRecording: this._stopVideoRecording,
        takeScreenshot: this._takeScreenshot,
        takeHighResolutionPhoto: this._takeHighResolutionPhoto,
        isNativeARSessionAvailable: this._isNativeARSessionAvailable,
        resetARSession: this._resetARSession,
        setWorldOrigin: this._setWorldOrigin,
        project: this._project,
        unproject: this._unproject,
        hostCloudAnchor: this._hostCloudAnchor,
        resolveCloudAnchor: this._resolveCloudAnchor,
        cancelCloudAnchorOperations: this._cancelCloudAnchorOperations,
        addAnchor: this._addAnchor,
        createAndHostCloudAnchor: this._createAndHostCloudAnchor,
        // Geospatial API
        isGeospatialModeSupported: this._isGeospatialModeSupported,
        setGeospatialModeEnabled: this._setGeospatialModeEnabled,
        getEarthTrackingState: this._getEarthTrackingState,
        getCameraGeospatialPose: this._getCameraGeospatialPose,
        checkVPSAvailability: this._checkVPSAvailability,
        createGeospatialAnchor: this._createGeospatialAnchor,
        createTerrainAnchor: this._createTerrainAnchor,
        createRooftopAnchor: this._createRooftopAnchor,
        removeGeospatialAnchor: this._removeGeospatialAnchor,
        // Scene Semantics API
        isSemanticModeSupported: this._isSemanticModeSupported,
        setSemanticModeEnabled: this._setSemanticModeEnabled,
        getSemanticLabelFractions: this._getSemanticLabelFractions,
        getSemanticLabelFraction: this._getSemanticLabelFraction,
        // Monocular Depth Estimation API
        isMonocularDepthSupported: this._isMonocularDepthSupported,
        isMonocularDepthModelDownloaded: this._isMonocularDepthModelDownloaded,
        setMonocularDepthEnabled: this._setMonocularDepthEnabled,
        setMonocularDepthModelURL: this._setMonocularDepthModelURL,
        downloadMonocularDepthModel: this._downloadMonocularDepthModel,
        setPreferMonocularDepth: this._setPreferMonocularDepth,
        isPreferMonocularDepth: this._isPreferMonocularDepth,
        // World Map Persistence API (iOS only) - imperative methods
        saveWorldMap: this._saveWorldMap,
        loadWorldMap: this._loadWorldMap,
        deleteWorldMap: this._deleteWorldMap,
        getWorldMappingStatus: this._getWorldMappingStatus,
        // Frame Streaming API (iOS only, for Gemini Vision integration)
        startFrameStream: this._startFrameStream,
        stopFrameStream: this._stopFrameStream,
        resolveDetections: this._resolveDetections,
        // View Transform Zoom API
        setViewZoom: this._setViewZoom,
        // Render Zoom API (Projection-Based)
        setRenderZoom: this._setRenderZoom,
        getRenderZoom: this._getRenderZoom,
        getMaxRenderZoom: this._getMaxRenderZoom,
        setMaxRenderZoom: this._setMaxRenderZoom,
        viroAppProps: {},
    };
    sceneNavigator = {
        push: this.push,
        pop: this.pop,
        popN: this.popN,
        jump: this.jump,
        replace: this.replace,
        startVideoRecording: this._startVideoRecording,
        stopVideoRecording: this._stopVideoRecording,
        takeScreenshot: this._takeScreenshot,
        takeHighResolutionPhoto: this._takeHighResolutionPhoto,
        isNativeARSessionAvailable: this._isNativeARSessionAvailable,
        resetARSession: this._resetARSession,
        setWorldOrigin: this._setWorldOrigin,
        project: this._project,
        unproject: this._unproject,
        hostCloudAnchor: this._hostCloudAnchor,
        resolveCloudAnchor: this._resolveCloudAnchor,
        cancelCloudAnchorOperations: this._cancelCloudAnchorOperations,
        addAnchor: this._addAnchor,
        createAndHostCloudAnchor: this._createAndHostCloudAnchor,
        // Geospatial API
        isGeospatialModeSupported: this._isGeospatialModeSupported,
        setGeospatialModeEnabled: this._setGeospatialModeEnabled,
        getEarthTrackingState: this._getEarthTrackingState,
        getCameraGeospatialPose: this._getCameraGeospatialPose,
        checkVPSAvailability: this._checkVPSAvailability,
        createGeospatialAnchor: this._createGeospatialAnchor,
        createTerrainAnchor: this._createTerrainAnchor,
        createRooftopAnchor: this._createRooftopAnchor,
        removeGeospatialAnchor: this._removeGeospatialAnchor,
        // Scene Semantics API
        isSemanticModeSupported: this._isSemanticModeSupported,
        setSemanticModeEnabled: this._setSemanticModeEnabled,
        getSemanticLabelFractions: this._getSemanticLabelFractions,
        getSemanticLabelFraction: this._getSemanticLabelFraction,
        // Monocular Depth Estimation API
        isMonocularDepthSupported: this._isMonocularDepthSupported,
        isMonocularDepthModelDownloaded: this._isMonocularDepthModelDownloaded,
        setMonocularDepthEnabled: this._setMonocularDepthEnabled,
        setMonocularDepthModelURL: this._setMonocularDepthModelURL,
        downloadMonocularDepthModel: this._downloadMonocularDepthModel,
        setPreferMonocularDepth: this._setPreferMonocularDepth,
        isPreferMonocularDepth: this._isPreferMonocularDepth,
        // World Map Persistence API (iOS only) - imperative methods
        saveWorldMap: this._saveWorldMap,
        loadWorldMap: this._loadWorldMap,
        deleteWorldMap: this._deleteWorldMap,
        getWorldMappingStatus: this._getWorldMappingStatus,
        // Frame Streaming API (iOS only, for Gemini Vision integration)
        startFrameStream: this._startFrameStream,
        stopFrameStream: this._stopFrameStream,
        resolveDetections: this._resolveDetections,
        // View Transform Zoom API
        setViewZoom: this._setViewZoom,
        // Render Zoom API (Projection-Based)
        setRenderZoom: this._setRenderZoom,
        getRenderZoom: this._getRenderZoom,
        getMaxRenderZoom: this._getMaxRenderZoom,
        setMaxRenderZoom: this._setMaxRenderZoom,
        viroAppProps: {},
    };
    render() {
        // Uncomment this line to check for misnamed props
        //checkMisnamedProps("ViroARSceneNavigator", this.props);
        const items = this._renderSceneStackItems();
        // update the arSceneNavigator with the latest given props on every render
        this.arSceneNavigator.viroAppProps = this.props.viroAppProps;
        this.sceneNavigator.viroAppProps = this.props.viroAppProps;
        // If the user simply passes us the props from the root React component,
        // then we'll have an extra 'rootTag' key which React automatically includes
        // so remove it.
        if (this.arSceneNavigator.viroAppProps?.rootTag) {
            delete this.arSceneNavigator.viroAppProps?.rootTag;
        }
        if (this.sceneNavigator.viroAppProps?.rootTag) {
            delete this.sceneNavigator.viroAppProps?.rootTag;
        }
        const { viroAppProps = {} } = this.props;
        return (<VRTARSceneNavigator ref={(component) => {
                this._component = component;
            }} {...this.props} viroAppProps={viroAppProps} currentSceneIndex={this.state.currentSceneIndex} style={(this.props.style, styles.container)}>
        {items}
      </VRTARSceneNavigator>);
    }
}
/**
 * ViroARSceneNavigator with ref support for imperative world map persistence API.
 *
 * @example
 * ```tsx
 * const ref = useRef<ViroARSceneNavigatorHandle>(null);
 *
 * <ViroARSceneNavigator ref={ref} ... />
 *
 * // Save world map
 * await ref.current?.saveWorldMap("my-session");
 *
 * // Load world map (restarts AR session)
 * await ref.current?.loadWorldMap("my-session");
 *
 * // Delete world map
 * await ref.current?.deleteWorldMap("my-session");
 * ```
 */
exports.ViroARSceneNavigator = React.forwardRef((props, ref) => {
    const innerRef = React.useRef(null);
    React.useImperativeHandle(ref, () => ({
        saveWorldMap: (sessionId, filePath) => innerRef.current?._saveWorldMap(sessionId, filePath) ??
            Promise.resolve({
                success: false,
                error: "Component not mounted",
                code: "SESSION_UNAVAILABLE",
            }),
        loadWorldMap: (sessionId, filePath) => innerRef.current?._loadWorldMap(sessionId, filePath) ??
            Promise.resolve({
                success: false,
                error: "Component not mounted",
                code: "SESSION_UNAVAILABLE",
            }),
        deleteWorldMap: (sessionId) => innerRef.current?._deleteWorldMap(sessionId) ??
            Promise.resolve({
                success: false,
                error: "Component not mounted",
                code: "SESSION_UNAVAILABLE",
            }),
        getWorldMappingStatus: () => innerRef.current?._getWorldMappingStatus() ??
            Promise.resolve({
                mappingStatus: "notAvailable",
                trackingState: "notAvailable",
                canSave: false,
            }),
        getWorldMeshSnapshot: () => Promise.resolve({
            success: false,
            error: "On-demand mesh snapshots are not available. Use ARMeshAnchor events via onAnchorFound/Updated instead.",
        }),
    }));
    return <ViroARSceneNavigatorClass ref={innerRef} {...props}/>;
});
// Set display name for React DevTools
exports.ViroARSceneNavigator.displayName = "ViroARSceneNavigator";
const styles = react_native_1.StyleSheet.create({
    container: {
        flex: 1,
        justifyContent: "center",
        alignItems: "center",
    },
});
const VRTARSceneNavigator = (0, react_native_1.requireNativeComponent)("VRTARSceneNavigator", 
// @ts-ignore
ViroARSceneNavigatorClass, {
    nativeOnly: { currentSceneIndex: true },
});
