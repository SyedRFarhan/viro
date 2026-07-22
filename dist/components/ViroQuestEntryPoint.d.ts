import * as React from "react";
/**
 * Drop-in root component for VRActivity on Meta Quest.
 *
 * The library auto-registers this as 'VRQuestScene' when imported, so most
 * apps need no manual setup. ViroXRSceneNavigator (panel side) calls
 * setIntent() with the initial scene and renderer config before launching
 * VRActivity. This component reads that intent, mounts ViroVRSceneNavigator
 * with key={intentKey} (fresh stack per intent), and populates the bridge
 * viewTag so VRModuleOpenXR ops (recenterTracking, setPassthroughEnabled)
 * work without a direct ref to ViroVRSceneNavigator.
 */
export declare function ViroQuestEntryPoint(): React.JSX.Element | null;
