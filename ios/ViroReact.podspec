require 'json'

package = JSON.parse(File.read(File.join(__dir__, '../package.json')))

Pod::Spec.new do |s|
  s.name                = 'ViroReact'
  s.version             = package['version']
  s.summary             = 'Viro React Native library for AR/VR applications'
  s.source              = { :git => 'https://github.com/ReactVision/viro.git', :tag => "v#{s.version}" }
  s.homepage            = 'https://github.com/ReactVision/viro'
  s.license             = { :type => 'MIT', :file => '../LICENSE' }
  s.author              = 'ReactVision'
  s.requires_arc        = true
  s.platform            = :ios, '18.0'
  s.ios.deployment_target = '18.0'
  s.visionos.deployment_target = '1.0'

  # visionOS: CompositorServices drives the immersive render loop.
  s.visionos.frameworks = ['Metal', 'MetalKit', 'CompositorServices', 'ARKit']

  # iOS: frameworks required by source files compiled from the pod
  # (VRTObjectDetectorView uses AVFoundation + Accelerate; CoreVideo for CVPixelBuffer)
  s.ios.frameworks = ['AVFoundation', 'Accelerate', 'CoreVideo']

  # Base source files. The top-level ios/*.{h,m,mm} pairs (VRT3DSceneNavigator,
  # VRTGeometry, VRTManagedAnimation, VRTUIImageWrapper, VRTVRSceneNavigator, ...)
  # are part of the bridge too -- in the prebuilt era their symbols came from
  # libViroReact.a and their headers from dist/include, so ViroReact/** alone
  # was enough. Source builds need them matched explicitly.
  source_files_array = ['ViroReact/**/*.{h,m,mm,swift}', '*.{h,m,mm}']
  header_files_array = ['ViroReact/**/*.h', '*.h']

  # Include dist files if they exist (for release builds)
  if File.exist?(File.join(__dir__, 'dist/include'))
    source_files_array << 'dist/include/**/*.{h,m,mm}'
    header_files_array << 'dist/include/*.h'
  end

  # Consumers use the prebuilt bridge (like upstream, whose npm package is
  # dist-only; the source branch below never worked in consumer pod builds
  # -- clang-module/textual-include conflicts around ViroKit's C++ headers).
  # The staleness trap this once caused (lib frozen at v2.61.50 while three
  # releases shipped around it, Aug 23 2026) is closed by the prepack gate:
  # `npm publish` refuses to pack unless dist/lib/.source-hash matches the
  # current bridge sources. Rebuild with `npm run build:bridge`.
  lib_path = 'dist/lib/libViroReact.a'
  if File.exist?(File.join(__dir__, lib_path))
    # Prebuilt bridge: headers only, link the static lib.
    s.source_files = header_files_array
    s.public_header_files = header_files_array
    s.vendored_libraries = lib_path
  else
    # Repository builds compile the bridge from source.
    s.source_files = source_files_array
    s.public_header_files = header_files_array
    # Dead sources the ViroReact.xcodeproj target never compiled (the glob is
    # broader than the curated target list): VRTButton.mm and VROHUDManager.mm
    # import headers that do not exist anywhere in the tree; VROTextManager.mm
    # is orphaned. Keep this list in sync with the xcodeproj when adding files.
    s.ios.exclude_files = [
      'ViroReact/VisionOS/**/*',
      'ViroReact/Views/VRTButton.mm',
      'ViroReact/VROHUDManager.mm',
      'ViroReact/VROTextManager.mm',
    ]
  end

  # React Native dependencies
  s.dependency 'React-Core'
  s.dependency 'ViroKit'

  # ONNX Runtime is distributed as a vendored dynamic xcframework (onnxruntime.xcframework).
  # When the xcframework is present in ios/dist/Frameworks/, enable inference by setting:
  #   GCC_PREPROCESSOR_DEFINITIONS = $(inherited) VIRO_ONNXRUNTIME_AVAILABLE=1
  # Until then, VRTObjectDetectorView compiles with the camera pipeline active
  # and inference returning empty results.
  if File.exist?(File.join(__dir__, 'dist/Frameworks/onnxruntime.xcframework'))
    s.vendored_frameworks = [
      'dist/ViroRenderer/ViroKit.framework',
      'dist/Frameworks/onnxruntime.xcframework'
    ]
    onnx_preprocessor_definition = ' VIRO_ONNXRUNTIME_AVAILABLE=1'
  end
  # Fabric dependencies
  s.dependency 'React-RCTFabric'
  s.dependency 'React-Fabric'
  s.dependency 'React-FabricComponents'

  # Fabric-specific build configuration
  s.pod_target_xcconfig = {
    'SWIFT_VERSION' => '5.0',
    # ViroKit.framework carries a modulemap whose umbrella closure includes
    # C++ headers (std::shared_ptr et al). With clang modules on (the pod
    # default), any #import <ViroKit/...> from this pod attempts a module
    # build of that closure in an ObjC context and dies on '<memory>' not
    # found. The fork's own xcodeproj resolves these imports textually; do
    # the same here. (iOS compiles no Swift in this pod - VisionOS only.)
    'CLANG_ENABLE_MODULES' => 'NO',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/ViroReact"',
      '"$(PODS_TARGET_SRCROOT)/ViroReact/VROCapture"',
      '"$(PODS_TARGET_SRCROOT)/dist/include"',
      '"$(PODS_ROOT)/Headers/Public"',
      '"$(PODS_ROOT)/Headers/Public/ViroKit"',
      '"$(PODS_ROOT)/ViroKit/dist/include"',
      '"$(PODS_ROOT)/ViroKit/Headers"'
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => "$(inherited) RCT_NEW_ARCH_ENABLED=1#{onnx_preprocessor_definition}",
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=c++17'
  }

end
