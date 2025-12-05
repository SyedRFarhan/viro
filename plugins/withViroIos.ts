import {
  ConfigPlugin,
  ExportedConfigWithProps,
  XcodeProject,
  withDangerousMod,
  withPlugins,
  withXcodeProject,
  WarningAggregator,
} from "@expo/config-plugins";
import { ExpoConfig } from "@expo/config-types";
import fs from "fs";
import { insertLinesHelper } from "./util/insertLinesHelper";
import { DEFAULTS, ViroConfigurationOptions } from "./withViro";

const withViroPods = (config: ExpoConfig) => {
  config = withDangerousMod(config, [
    "ios",
    async (newConfig) => {
      const root = newConfig.modRequest.platformProjectRoot;

      // Check if cloud anchors are enabled
      let cloudAnchorProvider: string | undefined;
      if (Array.isArray(config.plugins)) {
        const pluginConfig = config?.plugins?.find(
          (plugin) =>
            Array.isArray(plugin) && plugin[0] === "@reactvision/react-viro"
        );
        if (Array.isArray(pluginConfig) && pluginConfig.length > 1) {
          const options = pluginConfig[1] as ViroConfigurationOptions;
          cloudAnchorProvider = options.cloudAnchorProvider;
        }
      }

      fs.readFile(`${root}/Podfile`, "utf-8", (err, data) => {
        // Check for New Architecture environment variable
        if (
          !data.includes('ENV["RCT_NEW_ARCH_ENABLED"]') &&
          !data.includes("RCT_NEW_ARCH_ENABLED=1")
        ) {
          WarningAggregator.addWarningIOS(
            "withViroIos",
            "ViroReact requires New Architecture to be enabled. " +
              "Please set RCT_NEW_ARCH_ENABLED=1 in your ios/.xcode.env file."
          );
        }

        // ViroReact with integrated Fabric support
        let viroPods =
          `  # ViroReact with integrated New Architecture (Fabric) support\n` +
          `  # Automatically includes Fabric components when RCT_NEW_ARCH_ENABLED=1\n` +
          `  pod 'ViroReact', :path => '../node_modules/@reactvision/react-viro/ios'\n` +
          `  pod 'ViroKit', :path => '../node_modules/@reactvision/react-viro/ios/dist/ViroRenderer/'`;

        // Add ARCore Cloud Anchors pod if enabled
        if (cloudAnchorProvider === "arcore") {
          viroPods +=
            `\n\n  # ARCore Cloud Anchors - Cross-platform anchor sharing\n` +
            `  # Requires GARAPIKey in Info.plist and use_frameworks! with dynamic linkage\n` +
            `  pod 'ARCore/CloudAnchors', '~> 1.51.0'`;
        }

        // Add use_frameworks! for ARCore Cloud Anchors (must be before pods)
        if (cloudAnchorProvider === "arcore") {
          // Insert use_frameworks! before the target block
          // This is unconditional (not behind an if statement) so it will always apply
          data = insertLinesHelper(
            `# ARCore SDK requires dynamic frameworks\nuse_frameworks! :linkage => :dynamic\n`,
            "target '",
            data,
            -1
          );
        }

        // Add New Architecture enforcement
        viroPods +=
          `\n\n  # Enforce New Architecture requirement\n` +
          `  # ViroReact 2.43.1+ requires React Native New Architecture\n` +
          `  if ENV['RCT_NEW_ARCH_ENABLED'] != '1'\n` +
          `    raise "ViroReact requires New Architecture to be enabled. Please set RCT_NEW_ARCH_ENABLED=1 in ios/.xcode.env"\n` +
          `  end`;

        // Insert the pods into the Podfile
        data = insertLinesHelper(
          viroPods,
          "post_install do |installer|",
          data,
          -1
        );

        fs.writeFile(`${root}/Podfile`, data, "utf-8", function (err) {
          if (err) console.log("Error writing Podfile");
        });
      });
      return newConfig;
    },
  ]);

  return config;
};

const withEnabledBitcode: ConfigPlugin = (config) =>
  withXcodeProject(config, async (newConfig) => {
    newConfig.modResults.addBuildProperty("ENABLE_BITCODE", "NO", "Release");
    return newConfig;
  });

const setExcludedArchitectures = (
  project: ExportedConfigWithProps<XcodeProject>["modResults"]
) => {
  const configurations = project.pbxXCBuildConfigurationSection();

  // @ts-ignore
  for (const { buildSettings } of Object.values(configurations || {})) {
    if (
      typeof (buildSettings === null || buildSettings === void 0
        ? void 0
        : buildSettings.PRODUCT_NAME) !== "undefined"
    ) {
      buildSettings['"EXCLUDED_ARCHS[sdk=iphonesimulator*]"'] = '"arm64"';
    }
  }

  return project;
};

const withExcludedSimulatorArchitectures = (config: ExpoConfig) => {
  return withXcodeProject(config, (newConfig) => {
    newConfig.modResults = setExcludedArchitectures(newConfig.modResults);
    return newConfig;
  });
};

export const withDefaultInfoPlist: ConfigPlugin<ViroConfigurationOptions> = (
  config,
  props
) => {
  let savePhotosPermission = DEFAULTS.ios.savePhotosPermission;
  let photosPermission = DEFAULTS.ios.photosPermission;
  let cameraUsagePermission = DEFAULTS.ios.cameraUsagePermission;
  let microphoneUsagePermission = DEFAULTS.ios.microphoneUsagePermission;
  let googleCloudApiKey: string | undefined;
  let cloudAnchorProvider: string | undefined;

  if (Array.isArray(config.plugins)) {
    const pluginConfig = config?.plugins?.find(
      (plugin) =>
        Array.isArray(plugin) && plugin[0] === "@reactvision/react-viro"
    );
    if (Array.isArray(pluginConfig) && pluginConfig.length > 1) {
      const pluginOptions = pluginConfig[1] as ViroConfigurationOptions;
      savePhotosPermission =
        pluginOptions.ios?.savePhotosPermission || savePhotosPermission;
      photosPermission = pluginOptions.ios?.photosPermission || photosPermission;
      microphoneUsagePermission =
        pluginOptions.ios?.microphoneUsagePermission || microphoneUsagePermission;
      cameraUsagePermission =
        pluginOptions.ios?.cameraUsagePermission || cameraUsagePermission;
      googleCloudApiKey = pluginOptions.googleCloudApiKey;
      cloudAnchorProvider = pluginOptions.cloudAnchorProvider;
    }
  }

  if (!config.ios) config.ios = {};
  if (!config.ios.infoPlist) config.ios.infoPlist = {};
  config.ios.infoPlist.NSPhotoLibraryUsageDescription =
    config.ios.infoPlist.NSPhotoLibraryUsageDescription || photosPermission;
  config.ios.infoPlist.NSPhotoLibraryAddUsageDescription =
    config.ios.infoPlist.NSPhotoLibraryAddUsageDescription ||
    savePhotosPermission;
  config.ios.infoPlist.NSCameraUsageDescription =
    config.ios.infoPlist.NSCameraUsageDescription || cameraUsagePermission;
  config.ios.infoPlist.NSMicrophoneUsageDescription =
    config.ios.infoPlist.NSMicrophoneUsageDescription ||
    microphoneUsagePermission;

  // Add Google Cloud API key for ARCore Cloud Anchors (iOS)
  if (googleCloudApiKey && cloudAnchorProvider === "arcore") {
    config.ios.infoPlist.GARAPIKey = googleCloudApiKey;
  }

  return config;
};

export const withViroIos: ConfigPlugin<ViroConfigurationOptions> = (
  config,
  props
) => {
  withPlugins(config, [[withViroPods, props]]);
  withDefaultInfoPlist(config, props);
  withEnabledBitcode(config);
  withExcludedSimulatorArchitectures(config);
  return config;
};
