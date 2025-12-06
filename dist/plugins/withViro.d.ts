import { ConfigPlugin } from "@expo/config-plugins";
export type XrMode = "GVR" | "AR" | "OVR_MOBILE";
/**
 * Cloud Anchors provider type.
 * - "none": Cloud Anchors disabled
 * - "arcore": Use ARCore Cloud Anchors (works on both iOS and Android)
 */
export type CloudAnchorProvider = "none" | "arcore";
/**
 * Geospatial Anchor provider type.
 * - "none": Geospatial API disabled
 * - "arcore": Use ARCore Geospatial API (works on both iOS and Android)
 */
export type GeospatialAnchorProvider = "none" | "arcore";
/**
 * Options interface for configuring expo plugin
 */
export interface ViroConfigurationOptions {
    /**
     * Google Cloud API key for ARCore Cloud Anchors and Geospatial API.
     * Required if using cloudAnchorProvider: "arcore" or geospatialAnchorProvider: "arcore"
     *
     * Get your API key from Google Cloud Console:
     * https://console.cloud.google.com/apis/credentials
     *
     * Make sure to enable the ARCore API for your project.
     */
    googleCloudApiKey?: string;
    /**
     * Cloud Anchors provider for cross-platform anchor sharing.
     * When set to "arcore", enables ARCore Cloud Anchors on both iOS and Android.
     *
     * DEFAULTS TO: "none"
     */
    cloudAnchorProvider?: CloudAnchorProvider;
    /**
     * Geospatial Anchor provider for location-based AR.
     * When set to "arcore", enables ARCore Geospatial API on both iOS and Android.
     * Requires googleCloudApiKey to be set.
     *
     * DEFAULTS TO: "none"
     */
    geospatialAnchorProvider?: GeospatialAnchorProvider;
    ios?: {
        /**
         * String for app to use for camera usage.
         *
         * DEFAULTS TO: 'Allow $(PRODUCT_NAME) to use your camera'
         */
        cameraUsagePermission?: string;
        /**
         * String for app to use for microphone usage.
         *
         * DEFAULTS TO: "Allow $(PRODUCT_NAME) to use your microphone"
         */
        microphoneUsagePermission?: string;
        /**
         * String for app to read photos.
         *
         * DEFAULTS TO: 'Allow $(PRODUCT_NAME) to access your photos'
         */
        photosPermission?: string;
        /**
         * String for app to save photos
         *
         * DEFAULTS TO: 'Allow $(PRODUCT_NAME) to save photos'
         */
        savePhotosPermission?: string;
        /**
         * String for app to use location (required for Geospatial API)
         *
         * DEFAULTS TO: 'Allow $(PRODUCT_NAME) to use your location for AR experiences'
         */
        locationUsagePermission?: string;
    };
    android?: {
        xRMode?: XrMode[];
    };
}
/**
 * Default options
 */
export declare const DEFAULTS: {
    ios: {
        cameraUsagePermission: string;
        microphoneUsagePermission: string;
        photosPermission: string;
        savePhotosPermission: string;
        locationUsagePermission: string;
    };
    android: {
        xRMode: string[];
    };
};
/**
 * Configures Viro to work with Expo projects.
 *
 * IMPORTANT: This plugin requires React Native New Architecture (Fabric) to be enabled.
 * ViroReact 2.43.1+ only supports New Architecture.
 *
 * @param config Expo ConfigPlugin
 * @returns expo configuration
 */
declare const withViro: ConfigPlugin<ViroConfigurationOptions>;
export default withViro;
