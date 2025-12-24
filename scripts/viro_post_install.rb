# ViroKit ARCore Weak Linking Post-Install Hook
#
# This script enables optional ARCore integration by adding weak framework links
# only when ARCore pods are installed. This prevents linker errors when ARCore
# is not included in the project.
#
# Usage: Add to your Podfile's post_install hook:
#
#   post_install do |installer|
#     # ... existing post_install code ...
#
#     # ViroKit ARCore weak linking
#     viro_arcore_weak_link(installer)
#   end
#

def viro_arcore_weak_link(installer)
  puts "🔧 [ViroKit] Configuring ARCore weak linking..."

  # Map of ARCore pods to their framework names
  # ARCore is distributed as separate sub-frameworks via xcframeworks
  arcore_pod_to_frameworks = {
    'ARCore' => ['ARCoreBase', 'ARCoreGARSession', 'ARCoreTFShared'],
    'PromisesObjC' => ['FBLPromises'],
    'GoogleDataTransport' => ['GoogleDataTransport'],
    'GoogleUtilities' => ['GoogleUtilities']
  }

  # Additional ARCore subspecs that may be installed
  arcore_subspec_frameworks = {
    'CloudAnchors' => 'ARCoreCloudAnchors',
    'Geospatial' => 'ARCoreGeospatial',
    'Semantics' => 'ARCoreSemantics'
  }

  # Detect which ARCore-related pods are installed
  installed_pods = installer.pods_project.targets.map(&:name)
  weak_frameworks = []

  # Check for base ARCore pods and their frameworks
  arcore_pod_to_frameworks.each do |pod_name, frameworks|
    if installed_pods.any? { |target| target.start_with?(pod_name) }
      weak_frameworks.concat(frameworks)
      puts "   ✓ Found #{pod_name} - will weak link: #{frameworks.join(', ')}"
    end
  end

  # Check for ARCore subspecs
  arcore_subspec_frameworks.each do |subspec, framework|
    if installed_pods.any? { |target| target.include?("ARCore") && target.include?(subspec) }
      weak_frameworks << framework
      puts "   ✓ Found ARCore/#{subspec} - will weak link: #{framework}"
    end
  end

  if weak_frameworks.empty?
    puts "   ℹ️  No ARCore pods detected - ViroKit will run without ARCore features"
    puts "   ℹ️  To enable ARCore, add to your Podfile:"
    puts "      pod 'ARCore/CloudAnchors', '~> 1.51.0'"
    puts "      pod 'ARCore/Geospatial', '~> 1.51.0'"
    puts "      pod 'ARCore/Semantics', '~> 1.51.0'"
    return
  end

  puts "   🎯 Applying weak linking for: #{weak_frameworks.uniq.join(', ')}"

  # Find targets that link ViroKit
  installer.pods_project.targets.each do |target|
    # Apply to the app target and any target that depends on ViroKit
    next unless target.name.include?('ViroKit') ||
                target.dependencies.any? { |dep| dep.name.include?('ViroKit') }

    puts "   📦 Updating target: #{target.name}"

    target.build_configurations.each do |config|
      # Get current OTHER_LDFLAGS
      other_ldflags = config.build_settings['OTHER_LDFLAGS'] || ['$(inherited)']
      other_ldflags = [other_ldflags] if other_ldflags.is_a?(String)

      # Add weak framework flags for each detected ARCore framework
      weak_frameworks.uniq.each do |framework|
        unless other_ldflags.include?("-weak_framework") && other_ldflags.include?(framework)
          other_ldflags << '-weak_framework'
          other_ldflags << framework
        end
      end

      config.build_settings['OTHER_LDFLAGS'] = other_ldflags
    end
  end

  puts "   ✅ ViroKit ARCore weak linking configured successfully"
end
