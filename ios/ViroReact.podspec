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
  
  # Check for prebuilt library
  lib_path = 'dist/lib/libViroReact.a'
  has_prebuilt_lib = File.exist?(File.join(__dir__, lib_path))

  if has_prebuilt_lib
    # If prebuilt lib exists, only include headers in source_files and vendor the lib
    s.source_files = ['ViroReact/**/*.h', 'dist/include/**/*.h']
    s.public_header_files = ['ViroReact/**/*.h', 'dist/include/**/*.h']
    s.vendored_libraries = lib_path
  else
    # Otherwise fallback to building from source
    source_files_array = ['ViroReact/**/*.{h,m,mm}']
    if File.exist?(File.join(__dir__, 'dist/include'))
      source_files_array << 'dist/include/**/*.{h,m,mm}'
    end
    s.source_files = source_files_array
    s.public_header_files = ['ViroReact/**/*.h', 'dist/include/**/*.h']
  end

  # React Native dependencies
  s.dependency 'React-Core'
  s.dependency 'ViroKit'
  
  # Fabric dependencies
  s.dependency 'React-RCTFabric'
  s.dependency 'React-Fabric'
  s.dependency 'React-FabricComponents'
  
  # Fabric-specific build configuration
  s.pod_target_xcconfig = {
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
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) RCT_NEW_ARCH_ENABLED=1',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=c++17'
  }
  
end
