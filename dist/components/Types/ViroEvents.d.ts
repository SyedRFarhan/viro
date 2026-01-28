/**
 * Copyright (c) 2021-present, Viro Media, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 * To do
 * - source types
 * - clickState types
 */
import { ViroARTrackingReasonConstants, ViroTrackingStateConstants } from "../ViroConstants";
import { Viro3DPoint, ViroRotation, ViroSource } from "./ViroUtils";
export type ViroHoverEvent = {
    isHovering: boolean;
    position: Viro3DPoint;
    source: ViroSource;
};
export type ViroClickEvent = {
    position: Viro3DPoint;
    source: ViroSource;
};
export type ViroClickStateEvent = {
    clickState: ViroClickState;
    position: Viro3DPoint;
    source: ViroSource;
};
export type ViroClickState = ViroClickStateTypes.CLICK_DOWN | ViroClickStateTypes.CLICK_UP | ViroClickStateTypes.CLICKED;
export declare enum ViroClickStateTypes {
    CLICK_DOWN = 1,// Click Down: Triggered when the user has performed a click down action while hovering on this control.|
    CLICK_UP = 2,// Click Up: Triggered when the user has performed a click up action while hovering on this control.|
    CLICKED = 3
}
export type ViroTouchEvent = {
    touchState: any;
    touchPos: Viro3DPoint;
    source: ViroSource;
};
export type ViroScrollEvent = {
    scrollPos: Viro3DPoint;
    source: ViroSource;
};
export type ViroSwipeEvent = {
    swipeState: any;
    source: ViroSource;
};
export type ViroFuseEvent = {
    source: ViroSource;
};
export type ViroPinchEvent = {
    pinchState: ViroPinchState;
    scaleFactor: number;
    source: ViroSource;
};
export type ViroPinchState = ViroPinchStateTypes.PINCH_START | ViroPinchStateTypes.PINCH_MOVE | ViroPinchStateTypes.PINCH_END;
export declare enum ViroPinchStateTypes {
    PINCH_START = 1,// Triggered when the user has started a pinch gesture.
    PINCH_MOVE = 2,// Triggered when the user has adjusted the pinch, moving both fingers.
    PINCH_END = 3
}
export type ViroRotateEvent = {
    rotateState: ViroRotateState;
    rotationFactor: number;
    source: ViroSource;
};
export type ViroRotateState = ViroRotateStateTypes.ROTATE_START | ViroRotateStateTypes.ROTATE_MOVE | ViroRotateStateTypes.ROTATE_END;
export declare enum ViroRotateStateTypes {
    ROTATE_START = 1,// Triggered when the user has started a rotation gesture.
    ROTATE_MOVE = 2,// Triggered when the user has adjusted the rotation, moving both fingers.
    ROTATE_END = 3
}
export type ViroDragEvent = {
    dragToPos: Viro3DPoint;
    source: ViroSource;
};
export type ViroPlatformEvent = {
    platformInfoViro: ViroPlatformInfo;
};
export type ViroCollisionEvent = {
    viroTag: string;
    collidedPoint: Viro3DPoint;
    collidedNormal: Viro3DPoint;
};
/**
 * Platform information for the current device.
 *
 * | |iOS Cardboard|Android Cardboard| Daydream | GearVR
 * |-------------------|---------------|---------------|---------------|---------------|
 * |Platform|gvr|gvr|gvr|ovr-mobile|
 * |Headset|cardboard|cardboard|daydream|gearvr|
 * |Controller|cardboard|cardboard|daydream|gearvr|
 */
export type ViroPlatformInfo = {
    platform: ViroPlatformTypes;
    /** @deprecated */
    vrPlatform: ViroPlatformTypes;
    headset: ViroHeadsetTypes;
    controller: ViroControllerTypes;
};
export declare enum ViroPlatformTypes {
    GVR = "gvr",
    GEAR_VR = "ovr-mobile"
}
export declare enum ViroHeadsetTypes {
    CARDBOARD = "cardboard",
    DAYDREAM = "daydream",
    GEARVR = "gearvr"
}
export declare enum ViroControllerTypes {
    CARDBOARD = "cardboard",
    DAYDREAM = "daydream",
    GEARVR = "gearvr"
}
export type ViroCameraTransformEvent = {
    cameraTransform: number[];
};
export type ViroPlatformUpdateEvent = {
    platformInfoViro: ViroPlatformInfo;
};
export type ViroCameraTransform = {
    /** @deprecated The cameraTransform key will be deprecated in a future release */
    cameraTransform: {
        position: Viro3DPoint;
        rotation: ViroRotation;
        forward: Viro3DPoint;
        up: Viro3DPoint;
    };
    position: Viro3DPoint;
    rotation: ViroRotation;
    forward: Viro3DPoint;
    up: Viro3DPoint;
};
export type ViroExitViroEvent = {};
export type ViroErrorEvent = {
    error: Error;
};
/** ===========================================================================
 * Viro Animation Events
 * ============================================================================ */
export type ViroAnimationStartEvent = {};
export type ViroAnimationFinishEvent = {};
/** ===========================================================================
 * Viro Loading Events
 * ============================================================================ */
export type ViroLoadStartEvent = {};
export type ViroLoadEndEvent = {
    success: boolean;
};
export type ViroLoadErrorEvent = ViroErrorEvent;
/** ===========================================================================
 * Viro 360 Video Events
 * ============================================================================ */
export type ViroVideoBufferStartEvent = {};
export type ViroVideoBufferEndEvent = {};
export type ViroVideoUpdateTimeEvent = {
    currentTime: number;
    totalTime: number;
};
export type ViroVideoErrorEvent = ViroErrorEvent;
export type ViroVideoFinishEvent = ViroErrorEvent;
/** ===========================================================================
 * Viro Animated Component Events
 * ============================================================================ */
export type ViroAnimatedComponentStartEvent = {};
export type ViroAnimatedComponentFinishEvent = {};
/** ===========================================================================
 * Viro AR Anchor Events
 * ============================================================================ */
/**
 * Classification of detected planes.
 * iOS 12+ provides ML-based classification via ARKit.
 * Android provides basic inference from plane orientation.
 */
export type ViroARPlaneClassification = "None" | "Wall" | "Floor" | "Ceiling" | "Table" | "Seat" | "Door" | "Window" | "Unknown";
/**
 * Alignment of detected planes with respect to gravity.
 */
export type ViroARPlaneAlignment = "Horizontal" | "HorizontalUpward" | "HorizontalDownward" | "Vertical";
/**
 * Represents an AR anchor detected in the real world.
 */
export type ViroAnchor = {
    anchorId: string;
    type: "anchor" | "plane" | "image";
    position: [number, number, number];
    rotation: [number, number, number];
    scale: [number, number, number];
    center?: [number, number, number];
    width?: number;
    height?: number;
    alignment?: ViroARPlaneAlignment;
    classification?: ViroARPlaneClassification;
    vertices?: Array<[number, number, number]>;
    trackingMethod?: string;
};
export type ViroAnchorFoundMap = ViroAnchor;
export type ViroAnchorUpdatedMap = ViroAnchor;
export type ViroARAnchorRemovedEvent = {
    anchor: ViroAnchor;
};
export type ViroARAnchorUpdatedEvent = {
    anchorUpdatedMap: ViroAnchorUpdatedMap;
    anchor: ViroAnchor;
};
export type ViroARAnchorFoundEvent = {
    anchorFoundMap: ViroAnchorFoundMap;
    anchor: ViroAnchor;
};
/** ===========================================================================
 * Viro AR Plane Events
 * ============================================================================ */
export type ViroPlaneUpdatedMap = ViroAnchor;
export type ViroPlaneUpdatedEvent = any;
export type ViroARPlaneSizes = any;
/** ===========================================================================
 * Viro AR Hit Test
 * ============================================================================ */
export type ViroCameraARHitTestEvent = {
    hitTestResults: ViroARHitTestResult[];
    cameraOrientation: number[];
};
export type ViroCameraARHitTest = {
    hitTestResults: ViroARHitTestResult[];
    cameraOrientation: {
        position: Viro3DPoint;
        rotation: ViroRotation;
        forward: Viro3DPoint;
        up: Viro3DPoint;
    };
};
export type ViroARHitTestResult = any;
export type ViroARPointCloudUpdateEvent = {
    pointCloud: ViroARPointCloud;
};
export type ViroARPointCloud = any;
export type ViroTrackingUpdatedEvent = {
    state: ViroTrackingState;
    reason: ViroTrackingReason;
};
export type ViroTrackingState = ViroTrackingStateConstants.TRACKING_NORMAL | ViroTrackingStateConstants.TRACKING_LIMITED | ViroTrackingStateConstants.TRACKING_UNAVAILABLE;
export type ViroTrackingReason = ViroARTrackingReasonConstants.TRACKING_REASON_NONE | ViroARTrackingReasonConstants.TRACKING_REASON_EXCESSIVE_MOTION | ViroARTrackingReasonConstants.TRACKING_REASON_INSUFFICIENT_FEATURES | ViroARTrackingReasonConstants.TRACKING_REASON_INSUFFICIENT_LIGHT | ViroARTrackingReasonConstants.TRACKING_REASON_RELOCALIZING;
export type ViroAmbientLightUpdateEvent = {
    ambientLightInfo: ViroAmbientLightInfo;
};
export type ViroAmbientLightInfo = {
    intensity: number;
    color: string;
};
export type ViroWorldOrigin = {
    position: Viro3DPoint;
    rotation: ViroRotation;
};
export type ViroNativeTransformUpdateEvent = {
    position: Viro3DPoint;
};
export type ViroControllerStatusEvent = {
    controllerStatus: ViroControllerStatus;
    source: ViroSource;
};
export type ViroControllerStatus = any;
/** ===========================================================================
 * Viro AR Portal Events
 * ============================================================================ */
export type ViroPortalEnterEvent = any;
export type ViroPortalExitEvent = any;
/** ===========================================================================
 * Viro Sound Events
 * ============================================================================ */
export type ViroSoundFinishEvent = any;
/** ===========================================================================
 * Viro Cloud Anchor Events
 * ============================================================================ */
/**
 * State of a cloud anchor operation.
 * Maps to GARCloudAnchorState (iOS) and Anchor.CloudAnchorState (Android)
 */
export type ViroCloudAnchorState = "None" | "Success" | "ErrorInternal" | "TaskInProgress" | "ErrorNotAuthorized" | "ErrorResourceExhausted" | "ErrorHostingDatasetProcessingFailed" | "ErrorCloudIdNotFound" | "ErrorResolvingSdkVersionTooOld" | "ErrorResolvingSdkVersionTooNew" | "ErrorHostingServiceUnavailable";
/**
 * Cloud anchor provider type.
 */
export type ViroCloudAnchorProvider = "none" | "arcore";
/**
 * Represents a cloud-hosted AR anchor.
 */
export type ViroCloudAnchor = {
    /** The local anchor ID */
    anchorId: string;
    /** The cloud anchor ID (assigned after successful hosting) */
    cloudAnchorId?: string;
    /** Current state of the cloud anchor */
    state: ViroCloudAnchorState;
    /** Position in world coordinates */
    position: [number, number, number];
    /** Rotation in degrees */
    rotation: [number, number, number];
    /** Scale */
    scale: [number, number, number];
};
/**
 * Result of a host cloud anchor operation.
 * Includes anchor's world-space position and rotation for cross-device relocalization.
 */
export type ViroHostCloudAnchorResult = {
    success: boolean;
    cloudAnchorId?: string;
    error?: string;
    state: ViroCloudAnchorState;
    /** Anchor position in world space [x, y, z] */
    position?: [number, number, number];
    /** Anchor rotation in degrees [rx, ry, rz] - Euler angles */
    rotation?: [number, number, number];
};
/**
 * Result of a resolve cloud anchor operation.
 */
export type ViroResolveCloudAnchorResult = {
    success: boolean;
    anchor?: ViroCloudAnchor;
    error?: string;
    state: ViroCloudAnchorState;
};
/**
 * Result of an add anchor operation.
 * The anchorId can be used with hostCloudAnchor for cloud persistence.
 * Includes pose data: position [x,y,z] and cameraRotation (user's viewing orientation at anchor creation).
 */
export type ViroAddAnchorResult = {
    success: boolean;
    anchorId?: string;
    error?: string;
    /** Position as [x, y, z] */
    position?: [number, number, number];
    /** Camera rotation at anchor creation time as quaternion [x, y, z, w] */
    cameraRotation?: [number, number, number, number];
};
/**
 * Event fired when a cloud anchor state changes.
 */
export type ViroCloudAnchorStateChangeEvent = {
    anchorId: string;
    cloudAnchorId?: string;
    state: ViroCloudAnchorState;
    error?: string;
};
/** ===========================================================================
 * Viro Geospatial API Events and Types
 * ============================================================================ */
/**
 * Geospatial anchor provider type.
 */
export type ViroGeospatialAnchorProvider = "none" | "arcore";
/**
 * Earth tracking state.
 * Maps to GARSessionEarthState (iOS) and Earth.EarthState (Android)
 */
export type ViroEarthTrackingState = "Enabled" | "Paused" | "Stopped";
/**
 * VPS (Visual Positioning System) availability at a location.
 */
export type ViroVPSAvailability = "Available" | "Unavailable" | "Unknown";
/**
 * Type of geospatial anchor.
 */
export type ViroGeospatialAnchorType = "WGS84" | "Terrain" | "Rooftop";
/**
 * Quaternion representation [x, y, z, w] in East-Up-South (EUS) coordinate frame.
 */
export type ViroQuaternion = [number, number, number, number];
/**
 * The camera's geospatial pose including location, orientation, and accuracy.
 */
export type ViroGeospatialPose = {
    /** Latitude in degrees */
    latitude: number;
    /** Longitude in degrees */
    longitude: number;
    /** Altitude in meters above the WGS84 ellipsoid */
    altitude: number;
    /** Heading in degrees (0 = North, 90 = East) */
    heading: number;
    /** Orientation quaternion [x, y, z, w] in EUS frame */
    quaternion: ViroQuaternion;
    /** Horizontal accuracy in meters (95% confidence) */
    horizontalAccuracy: number;
    /** Vertical accuracy in meters (95% confidence) */
    verticalAccuracy: number;
    /** Heading accuracy in degrees (95% confidence) */
    headingAccuracy: number;
    /** Orientation yaw accuracy in degrees (95% confidence) */
    orientationYawAccuracy: number;
};
/**
 * Represents a geospatial anchor in the AR session.
 */
export type ViroGeospatialAnchor = {
    /** Unique identifier for this anchor */
    anchorId: string;
    /** Type of geospatial anchor */
    type: ViroGeospatialAnchorType;
    /** Latitude in degrees */
    latitude: number;
    /** Longitude in degrees */
    longitude: number;
    /** Altitude in meters */
    altitude: number;
    /** Heading in degrees */
    heading: number;
    /** Position in world coordinates [x, y, z] */
    position: [number, number, number];
};
/**
 * Result of checking geospatial mode support.
 */
export type ViroGeospatialSupportResult = {
    supported: boolean;
    error?: string;
};
/**
 * Result of getting Earth tracking state.
 */
export type ViroEarthTrackingStateResult = {
    state: ViroEarthTrackingState;
    error?: string;
};
/**
 * Result of getting the camera geospatial pose.
 */
export type ViroGeospatialPoseResult = {
    success: boolean;
    pose?: ViroGeospatialPose;
    error?: string;
};
/**
 * Result of checking VPS availability.
 */
export type ViroVPSAvailabilityResult = {
    availability: ViroVPSAvailability;
    error?: string;
};
/**
 * Result of creating a geospatial anchor.
 */
export type ViroCreateGeospatialAnchorResult = {
    success: boolean;
    anchor?: ViroGeospatialAnchor;
    error?: string;
};
/** ===========================================================================
 * Viro Scene Semantics API Types
 * ============================================================================ */
/**
 * Semantic labels for scene classification.
 * Each pixel in the camera feed can be classified into one of these categories.
 */
export type ViroSemanticLabel = "unlabeled" | "sky" | "building" | "tree" | "road" | "sidewalk" | "terrain" | "structure" | "object" | "vehicle" | "person" | "water";
/**
 * Semantic label fractions representing the percentage of pixels
 * for each label in the current frame.
 * Keys are semantic label names, values are fractions between 0.0 and 1.0.
 */
export type ViroSemanticLabelFractions = {
    unlabeled: number;
    sky: number;
    building: number;
    tree: number;
    road: number;
    sidewalk: number;
    terrain: number;
    structure: number;
    object: number;
    vehicle: number;
    person: number;
    water: number;
};
/**
 * Result of checking semantic mode support.
 */
export type ViroSemanticSupportResult = {
    supported: boolean;
    error?: string;
};
/**
 * Result of getting semantic label fractions.
 */
export type ViroSemanticLabelFractionsResult = {
    success: boolean;
    fractions?: ViroSemanticLabelFractions;
    error?: string;
};
/**
 * Result of getting a specific semantic label fraction.
 */
export type ViroSemanticLabelFractionResult = {
    success: boolean;
    fraction: number;
    error?: string;
};
/**
 * Result of checking monocular depth support.
 */
export type ViroMonocularDepthSupportResult = {
    supported: boolean;
    error?: string;
};
/**
 * Result of checking if monocular depth model is downloaded.
 */
export type ViroMonocularDepthModelDownloadedResult = {
    downloaded: boolean;
    error?: string;
};
/**
 * Result of downloading the monocular depth model.
 */
export type ViroMonocularDepthDownloadResult = {
    success: boolean;
    progress?: number;
    error?: string;
};
/**
 * Result of checking monocular depth preference.
 */
export type ViroMonocularDepthPreferenceResult = {
    preferred: boolean;
    error?: string;
};
/**
 * Result of getting the current render zoom factor.
 */
export type ViroRenderZoomResult = {
    zoomFactor: number;
    error?: string;
};
/**
 * Result of getting the maximum render zoom factor.
 */
export type ViroMaxRenderZoomResult = {
    maxZoomFactor: number;
    error?: string;
};
/**
 * Configuration for AR frame streaming.
 */
export type ViroFrameStreamConfig = {
    /** Enable/disable frame streaming */
    enabled: boolean;
    /** Target output width in pixels (e.g., 640) */
    width: number;
    /** Target output height in pixels (e.g., 480) */
    height: number;
    /** Target frames per second (1-5, default: 5) */
    fps: number;
    /** JPEG compression quality (0.0-1.0, default: 0.7) */
    quality: number;
};
/**
 * AR tracking state for frame events.
 */
export type ViroFrameTrackingState = "normal" | "limited" | "notAvailable";
/**
 * Camera intrinsics for the JPEG image.
 * Includes crop offsets applied during scale+crop encoding.
 */
export type ViroFrameIntrinsics = {
    /** Focal length X (in JPEG pixels) */
    fx: number;
    /** Focal length Y (in JPEG pixels) */
    fy: number;
    /** Principal point X (in JPEG pixels, crop-adjusted) */
    cx: number;
    /** Principal point Y (in JPEG pixels, crop-adjusted) */
    cy: number;
};
/**
 * Event payload for AR frame updates.
 * Contains the JPEG image and all data needed for 2D→3D mapping.
 */
export type ViroFrameEvent = {
    /** Unique ID for this capture (use with resolveDetections) */
    frameId: string;
    /** ARFrame timestamp */
    timestamp: number;
    /** Session ID (increments on AR session reset/relocalization) */
    sessionId: number;
    /** Base64-encoded JPEG image data */
    imageData: string;
    /** Exact image width in pixels */
    width: number;
    /** Exact image height in pixels */
    height: number;
    /** Camera intrinsics mapped to JPEG dimensions with crop offsets */
    intrinsics: ViroFrameIntrinsics;
    /** Camera pose at capture time (4x4 matrix, 16 elements, column-major) */
    cameraToWorld: number[];
    /**
     * Transform: JPEG normalized UV (0-1) → AR image normalized UV (0-1)
     * Use this to map JPEG coords back to AR image space (e.g., for depth lookup)
     * Format: [a, b, 0, c, d, 0, tx, ty, 1] (3x3 affine matrix as flat array)
     */
    jpegToARTransform: number[];
    /** Current AR tracking state */
    trackingState: ViroFrameTrackingState;
};
/**
 * Resolution method used for 2D→3D detection mapping.
 * Listed in order of preference/accuracy.
 */
export type ViroDetectionMethod = "lidar" | "raycast_geometry" | "raycast_infinite" | "raycast_estimated" | "pointcloud";
/**
 * Result of resolving a single 2D detection point to 3D.
 */
export type ViroDetectionResult = {
    /** Input point (normalized 0-1 UV in JPEG space) */
    input: {
        x: number;
        y: number;
    };
    /** Whether resolution succeeded */
    ok: boolean;
    /** World position [x, y, z] (valid if ok === true) */
    worldPos?: [number, number, number];
    /** Confidence level (0-1, varies by method) */
    confidence?: number;
    /** Resolution method used */
    method?: ViroDetectionMethod;
    /** Error message if resolution failed (ok === false) */
    error?: string;
};
/**
 * Result of resolving detections using capture-time data.
 */
export type ViroDetectionResolutionResult = {
    /** The frameId that was used for resolution */
    frameId: string;
    /** Array of resolution results (same order as input points) */
    results: ViroDetectionResult[];
    /** Error message if the entire operation failed */
    error?: string;
};
