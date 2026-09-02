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
    GEAR_VR = "ovr-mobile",
    QUEST = "quest"
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
 * Quest / OpenXR Hand Tracking Types (M4)
 * ============================================================================ */
export type ViroJoint = {
    position: Viro3DPoint;
    /** Sphere radius representing finger pad size (meters). */
    radius: number;
};
export type ViroHandJoints = {
    wrist: ViroJoint;
    thumbMetacarpal: ViroJoint;
    thumbProximal: ViroJoint;
    thumbDistal: ViroJoint;
    thumbTip: ViroJoint;
    indexMetacarpal: ViroJoint;
    indexProximal: ViroJoint;
    indexIntermediate: ViroJoint;
    indexDistal: ViroJoint;
    indexTip: ViroJoint;
    middleMetacarpal: ViroJoint;
    middleProximal: ViroJoint;
    middleIntermediate: ViroJoint;
    middleDistal: ViroJoint;
    middleTip: ViroJoint;
    ringMetacarpal: ViroJoint;
    ringProximal: ViroJoint;
    ringIntermediate: ViroJoint;
    ringDistal: ViroJoint;
    ringTip: ViroJoint;
    littleMetacarpal: ViroJoint;
    littleProximal: ViroJoint;
    littleIntermediate: ViroJoint;
    littleDistal: ViroJoint;
    littleTip: ViroJoint;
};
export type ViroHandPinchEvent = {
    hand: "left" | "right";
    /** World-space position of the pinch point (midpoint between thumb tip and index tip). */
    position: Viro3DPoint;
    /** Pinch strength [0..1] from XR_FB_hand_tracking_aim, or 1.0 on pinch-complete fallback. */
    pinchStrength: number;
};
/** Per-frame skeletal hand data dispatched via onHandUpdate. null when hand is not tracked. */
export type ViroHandUpdateEvent = {
    left: ViroHandJoints | null;
    right: ViroHandJoints | null;
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
    type: "anchor" | "plane" | "image" | "mesh";
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
export type ViroARHitTestResult = {
    type: "ExistingPlaneUsingExtent" | "ExistingPlane" | "EstimatedHorizontalPlane" | "FeaturePoint" | "DepthPoint";
    transform: {
        position: Viro3DPoint;
        rotation: ViroRotation;
        scale: Viro3DPoint;
    };
    hasDepthData: boolean;
    depthValue?: number;
    depthConfidence?: number;
    depthSource?: "lidar" | "monocular" | "arcore" | "none";
    /** @internal - Hit result ID for anchor creation, auto-generated */
    _hitResultId?: string;
};
/**
 * Reference to an AR node created from a hit test result.
 * Used to track anchored nodes and access their properties.
 */
export type ViroARNodeReference = {
    /** Unique identifier for the node */
    nodeId: string;
    /** React tag for the native view */
    reactTag: number;
    /** ID of the associated AR anchor */
    anchorId?: string;
    /** Current transform of the anchored node */
    transform?: {
        position: Viro3DPoint;
        rotation: ViroRotation;
        scale: Viro3DPoint;
    };
};
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
 * Unified AR provider — controls both cloud anchors and geospatial anchors.
 */
export type ViroProvider = "none" | "arcore" | "reactvision";
/** @deprecated Use ViroProvider */
export type ViroCloudAnchorProvider = ViroProvider;
/**
 * Represents a cloud-hosted AR anchor.
 *
 * `position`/`rotation` are always in world coordinates at resolve time — how
 * that world pose was originally anchored depends on how the anchor was
 * hosted: `hostCloudAnchor()` ties it to a hand-placed physical anchor;
 * `finishScan()` (room/building-scale scans, no placed anchor) ties it to a
 * self-defined location frame instead (origin at the scan's camera-position
 * centroid, oriented by the first keyframe's heading). Callers do not need to
 * know which one produced a given `cloudAnchorId` — both resolve to the same
 * world-space shape.
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
    /**
     * Opaque CSV-encoded transform for this resolved anchor (WS-C). Pass it
     * straight into `loadWorldMeshFromFile()` as `resolvedTransform` to attach
     * a mesh snapshot hosted alongside this anchor. Treat as opaque; do not
     * parse or construct this value.
     */
    resolvedTransform?: string;
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
 * Result of a finishScan() operation (WS-A room/building-scale scan, the
 * counterpart to ViroHostCloudAnchorResult for scans with no placed anchor).
 */
export type ViroFinishScanResult = {
    success: boolean;
    cloudAnchorId?: string;
    /**
     * Opaque token identifying the location frame this scan was hosted in.
     * Pass it straight into snapshotWorldMeshToFile() if attaching a mesh —
     * there is no placed anchor to derive one from otherwise. Treat as opaque;
     * do not parse or construct this value.
     */
    locationTransform?: string;
    error?: string;
};
/**
 * Result of snapshotWorldMeshToFile() (WS-C). filePath points at a local
 * cache file — pass it straight into rvUploadAsset() to persist it as a
 * cloud anchor asset.
 */
export type ViroWorldMeshSnapshotResult = {
    success: boolean;
    filePath?: string;
    error?: string;
};
/**
 * Result of loadWorldMeshFromFile() (WS-C). success is false if there was no
 * AR scene, world mesh was not enabled (see setWorldMeshEnabled), or the
 * file was malformed.
 */
export type ViroWorldMeshLoadResult = {
    success: boolean;
    error?: string;
};
/**
 * Result of a resolve cloud anchor operation. See {@link ViroCloudAnchor} for
 * how `anchor`'s pose relates to the original hosting method.
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
/** @deprecated Use ViroProvider */
export type ViroGeospatialAnchorProvider = ViroProvider;
/**
 * Earth tracking state.
 * Maps to GARSessionEarthState (iOS) and Earth.EarthState (Android)
 */
export type ViroEarthTrackingState = "Enabled" | "Paused" | "Stopped" | "Localizing";
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
 * Result of checking whether only approximate location is granted (WS-D).
 * When true, horizontalAccuracy will stay coarse and geospatial tracking
 * will never leave "Localizing" — surface an explicit error instead of
 * waiting on it to resolve on its own.
 */
export type ViroLocationAccuracyResult = {
    reduced: boolean;
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
 * Result of checking if monocular depth model is available (bundled).
 */
export type ViroMonocularDepthModelAvailableResult = {
    available: boolean;
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
 * Result of checking if depth occlusion is supported on this device.
 */
export type ViroDepthOcclusionSupportResult = {
    supported: boolean;
    minARCoreVersion?: string;
    error?: string;
};
/**
 * Result of checking geospatial setup prerequisites.
 */
export type ViroGeospatialSetupStatusResult = {
    geospatialSupported: boolean;
    locationServicesAvailable: boolean;
    apiKeyConfigured: boolean;
    arCoreVersion?: string;
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
    /**
     * When true (default), every frame event carries the base64 JPEG in
     * `imageData`. When false, events are metadata-only (~300 bytes) and image
     * bytes are fetched on demand via getFrameData(frameId) -- only frames that
     * are actually used pay the bridge cost.
     */
    includeImageData?: boolean;
    /** Per-frame native debug logging (default: false). */
    verbose?: boolean;
    /** Enable the eager hi-res second encode (default: false). */
    hiResEnabled?: boolean;
    /** Long-side cap of the hi-res variant in pixels (default: 1920). */
    hiResMaxDimension?: number;
    /** JPEG quality of the hi-res variant (default: 0.85). */
    hiResQuality?: number;
    /** How many recent frames keep their hi-res JPEG (default: 4). */
    hiResRingDepth?: number;
    /**
     * Container format of the hi-res variant (fork >= 2.61.70): 'heic'
     * halves bytes at equal quality (hardware encoder); silently falls
     * back to JPEG when unavailable. Check the `format` field on the
     * getFrameDataWithOptions result for what a frame actually holds.
     * @default 'jpeg'
     */
    hiResFormat?: "jpeg" | "heic";
    /** Run throttled on-device text recognition (default: false). */
    textLegibilityEnabled?: boolean;
    /** Minimum interval between OCR samples in ms (default: 1000). */
    textLegibilityIntervalMs?: number;
};
/** Options for getFrameDataWithOptions (fork >= 2.61.65). */
export type ViroFrameDataOptions = {
    /** 'hires' returns the high-resolution variant (errors if unavailable). */
    variant?: "hires";
    /**
     * Include this frame's LiDAR depth map: base64 float32 meters in
     * AR-IMAGE space (not JPEG space) plus arIntrinsics / arImage size /
     * jpegToARTransform for sampling it.
     */
    includeDepth?: boolean;
    /**
     * Depth encoding (fork >= 2.61.70): 'uint16mm' packs uint16
     * millimeters (0 = no data, clamped to 65.535m) at half the bytes.
     * The result's `depthFormat` field reports what was returned.
     * @default 'float32'
     */
    depthFormat?: "float32" | "uint16mm";
};
/**
 * Result of an on-demand getFrameData(frameId) fetch.
 * `imageData` is absent when the frame was evicted from the native ring
 * buffer (see `error`).
 */
export type ViroFrameDataResult = {
    frameId: string;
    /** Base64 JPEG. Absent when the frame is no longer available. */
    imageData?: string;
    timestamp?: number;
    /** Wall-clock shutter time, ms since epoch (fork >= 2.61.72). Frame age
        measured from here includes the encode and the bridge. */
    capturedAtEpochMs?: number;
    sessionId?: number;
    width?: number;
    height?: number;
    error?: string;
    /** ARCamera exposure duration (seconds) — the motion-blur signal. */
    exposureDuration?: number;
    rotatedToPortrait?: boolean;
    /** Flat 9 row-major JPEG-space intrinsics for the RETURNED variant. */
    intrinsics?: number[];
    /** Base64 float32 depth (meters), AR-image space, row-major, unpadded. */
    depthData?: string;
    depthWidth?: number;
    depthHeight?: number;
    /** Flat 9 row-major AR-image-space intrinsics (for depth sampling). */
    arIntrinsics?: number[];
    arImageWidth?: number;
    arImageHeight?: number;
    /** Flat 9 affine: landscape JPEG UV -> AR image UV. */
    jpegToARTransform?: number[];
    /** Mean luma, 0-1 over the pixel format's nominal range. */
    lumaMean?: number;
    /** 5th / 95th percentile luma, 0-1. */
    lumaP05?: number;
    lumaP95?: number;
    /** Fraction of sampled pixels at/above the clip threshold (blown). */
    clippedFraction?: number;
    /** Fraction of sampled pixels at/below the crush threshold (lost). */
    crushedFraction?: number;
    /** ARCamera exposureOffset (EV from calibrated) — darkness strain. */
    exposureOffset?: number;
    /** ARKit light estimate riders (absent when no estimate). */
    ambientIntensity?: number;
    ambientColorTemperature?: number;
    /** Depth confidence (fork >= 2.61.69): base64 uint8 per depth pixel,
        row-major, unpadded, same dims as depthData. 0=low 1=med 2=high. */
    depthConfidenceData?: string;
    /** Laplacian variance of the sampled luma plane (squared 8-bit luma
        units). Higher = sharper; motion blur and defocus both crush it.
        Rides with the lighting stats. */
    sharpness?: number;
    /** Container format of imageData: 'heic' only for hi-res frames
        encoded with hiResFormat: 'heic'. Absent on old clients. */
    format?: "jpeg" | "heic";
    /** Encoding of depthData ('float32' meters | 'uint16mm'). Absent on
        old clients (always float32 there). */
    depthFormat?: "float32" | "uint16mm";
    /** Text legibility (present only when this frame was OCR-sampled). */
    textBlockCount?: number;
    textMeanConfidence?: number;
    textMaxConfidence?: number;
    /** Tallest text observation's height, normalized 0-1 upright. */
    textMaxHeight?: number;
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
    /** Wall-clock shutter time, ms since epoch (fork >= 2.61.72). */
    capturedAtEpochMs?: number;
    /** ARCamera exposure duration (seconds) — the motion-blur proxy. */
    exposureDuration?: number;
    /** Mean / p05 / p95 luma, 0-1 over the format's nominal range. */
    lumaMean?: number;
    lumaP05?: number;
    lumaP95?: number;
    /** Fractions at the clip / crush thresholds (glare, lost shadows). */
    clippedFraction?: number;
    crushedFraction?: number;
    /** ARCamera exposureOffset (EV from calibrated). */
    exposureOffset?: number;
    /** ARKit light estimate riders (absent when no estimate). */
    ambientIntensity?: number;
    ambientColorTemperature?: number;
    /** Laplacian variance of the sampled luma plane — the direct blur
        measurement (rides with the lighting stats). */
    sharpness?: number;
    /** Latest throttled OCR sample (textLegibilityEnabled). The sample is
        usually a slightly older frame — textSampleAgeMs says how much. */
    textBlockCount?: number;
    textMeanConfidence?: number;
    textMaxConfidence?: number;
    /** Tallest text observation's height, normalized 0-1 upright — the
        "big enough to read" signal for hold-closer coaching. */
    textMaxHeight?: number;
    textSampleFrameId?: string;
    textSampleAgeMs?: number;
};
/**
 * Resolution method used for 2D→3D detection mapping.
 * Listed in order of preference/accuracy.
 */
export type ViroDetectionMethod = "lidar" | "raycast_geometry" | "mono" | "raycast_infinite" | "raycast_estimated" | "pointcloud";
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
    /**
     * The world-space ray through this pixel at capture pose (iOS, fork >=
     * 2.61.72). Present on every result: an unresolved point can still be
     * triangulated against a later sighting, and a resolved position should
     * lie on this ray.
     */
    ray?: {
        origin: [number, number, number];
        direction: [number, number, number];
    };
    /**
     * How many guessed rungs (infinite/estimated plane, point cloud) were
     * refused because they disagreed with the monocular depth at this pixel
     * (iOS, `monoDepthResolveEnabled`). Absent when zero.
     */
    gated?: number;
};
/**
 * A point to resolve: normalized 0-1 UV in the frame stream's JPEG space.
 * `box` (same space, [xmin, ymin, xmax, ymax]) is optional and lets the
 * monocular path run on a crop around the detection (`monoDepthCropEnabled`).
 */
export type ViroResolvePoint = {
    x: number;
    y: number;
    box?: [number, number, number, number];
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
