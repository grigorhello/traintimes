#!/usr/bin/env ruby
# Generates TrainTimes.xcodeproj (TT-101).
#
# The project uses Xcode 16 synchronized folders, so adding, moving or deleting a file under
# Sources/, Resources/, Preview Content/, Shared/, Widgets/ or Tests/ needs no project change. Re-run this script
# only to change targets, build settings or packages, then commit the regenerated project:
#
#   gem install xcodeproj   # once
#   ruby scripts/generate-xcodeproj.rb
#
# It runs on Linux too, which is how cloud sessions without Xcode change the project.

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'TrainTimes.xcodeproj')
BUNDLE_ID = 'ca.traintimes.TrainTimes'
DEPLOYMENT_TARGET = '17.0'
SNAPSHOT_TESTING_VERSION = '1.19.7'
# The app's version; the widget extension's must match it, or App Store Connect refuses the upload (TT-174).
MARKETING_VERSION = '1.0'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH, false, 77)
project.root_object.development_region = 'en-CA'
project.root_object.known_regions = ['en-CA', 'Base']
project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
project.root_object.attributes['LastUpgradeCheck'] = '1600'
project.root_object.attributes['BuildIndependentTargetsInParallel'] = '1'
project.root_object.preferred_project_object_version = '77'

def synced_group(project, path, parent = project.main_group)
  group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  group.path = path
  group.source_tree = '<group>'
  parent.children << group
  group
end

# Project-wide settings shared by every target and configuration.
COMMON = {
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
  'SDKROOT' => 'iphoneos',
  'SWIFT_VERSION' => '6.0',
  'SWIFT_STRICT_CONCURRENCY' => 'complete',
  'SWIFT_TREAT_WARNINGS_AS_ERRORS' => 'YES',
  'GCC_TREAT_WARNINGS_AS_ERRORS' => 'YES',
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
  'ENABLE_MODULE_VERIFIER' => 'YES',
  'CLANG_ENABLE_MODULES' => 'YES',
  'CLANG_ENABLE_OBJC_ARC' => 'YES',
  'LOCALIZATION_PREFERS_STRING_CATALOGS' => 'NO',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'TARGETED_DEVICE_FAMILY' => '1',
  'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS' => 'YES',
  'STRING_CATALOG_GENERATE_SYMBOLS' => 'NO',
  'DEAD_CODE_STRIPPING' => 'YES',
  'ALWAYS_SEARCH_USER_PATHS' => 'NO',
  'MTL_FAST_MATH' => 'YES'
}.freeze

project.build_configurations.each do |config|
  config.build_settings.merge!(COMMON)
  if config.name == 'Debug'
    config.build_settings.merge!(
      'DEBUG_INFORMATION_FORMAT' => 'dwarf',
      'ENABLE_TESTABILITY' => 'YES',
      'GCC_OPTIMIZATION_LEVEL' => '0',
      'ONLY_ACTIVE_ARCH' => 'YES',
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG $(inherited)',
      'SWIFT_OPTIMIZATION_LEVEL' => '-Onone',
      'MTL_ENABLE_DEBUG_INFO' => 'INCLUDE_SOURCE'
    )
  else
    config.build_settings.merge!(
      'DEBUG_INFORMATION_FORMAT' => 'dwarf-with-dsym',
      'ENABLE_NS_ASSERTIONS' => 'NO',
      'SWIFT_COMPILATION_MODE' => 'wholemodule',
      'VALIDATE_PRODUCT' => 'YES',
      'MTL_ENABLE_DEBUG_INFO' => 'NO'
    )
  end
end

# Folders (each one a synchronized group).
sources = synced_group(project, 'Sources')
resources = synced_group(project, 'Resources')
preview = synced_group(project, 'Preview Content')
# TT-174 (D67): Shared/ is compiled by the app and the widget extension (the Live Activity's attributes and views);
# Widgets/ by the extension alone.
shared = synced_group(project, 'Shared')
widgets_dir = synced_group(project, 'Widgets')
tests = project.main_group.new_group('Tests', 'Tests')
unit_tests_dir = synced_group(project, 'UnitTests', tests)
ui_tests_dir = synced_group(project, 'UITests', tests)

# App target.
app = project.new_target(:application, 'TrainTimes', :ios, DEPLOYMENT_TARGET, nil, :swift)
app.file_system_synchronized_groups << sources << resources << preview << shared
# Config/App.xcconfig: the app target's base configuration (TT-131; empty since D88, which moved the Metrolinx key to the alert server).
app_xcconfig = project.main_group.new_group('Config', 'Config').new_file('App.xcconfig')
app.build_configurations.each do |config|
  config.base_configuration_reference = app_xcconfig
  s = config.build_settings
  s.delete('INFOPLIST_FILE')
  s.merge!(
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'Accent', # TT-102: Resources/Colors.xcassets
    'TARGETED_DEVICE_FAMILY' => '1',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon', # Resources/AppIcon.xcassets (TT-103)
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    # D47: the TestFlight workflow sets CURRENT_PROJECT_VERSION to its run number when it archives.
    'MARKETING_VERSION' => MARKETING_VERSION,
    'CURRENT_PROJECT_VERSION' => '1',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Train Times',
    'INFOPLIST_KEY_LSApplicationCategoryType' => 'public.app-category.navigation',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
    # TT-171: asked only when a ride starts (On board); the background session also needs UIBackgroundModes location.
    'INFOPLIST_KEY_NSLocationWhenInUseUsageDescription' =>
      'Your location shows which station is next while you ride, and taps you before your stop.',
    # TT-176: asked only when the rider turns on "Detect my train" (the offer after the first completed ride, or Settings).
    'INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription' =>
      'Train Times notices when you’re on a GO train and offers On board. Your location stays on the phone.',
    # Keys with no INFOPLIST_KEY_ setting live in Config/Info.plist; Xcode merges the generated keys into it.
    # D49 reverses D25: no UIDesignRequiresCompatibility key, so iOS 26 draws Liquid Glass (TT-156).
    # D47: ITSAppUsesNonExemptEncryption NO answers export compliance (HTTPS only) for every upload (TT-154).
    # TT-171: UIBackgroundModes location keeps a ride's location going in the background (On board).
    # TT-174: NSSupportsLiveActivities for the ride's Live Activity, and the traintimes:// scheme its taps open.
    'INFOPLIST_FILE' => 'Config/Info.plist',
    'DEVELOPMENT_ASSET_PATHS' => '"Preview Content"',
    'ENABLE_PREVIEWS' => 'YES',
    'CODE_SIGN_STYLE' => 'Automatic',
    # TT-174: the TestFlight archive names each target's profile (scripts/testflight.sh); empty everywhere else.
    'PROVISIONING_PROFILE_SPECIFIER' => '$(TT_APP_PROFILE)',
    # TT-142: push notifications (aps-environment) so the app gets an APNs device token for alerts.
    'CODE_SIGN_ENTITLEMENTS' => 'Config/TrainTimes.entitlements',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
    'SWIFT_EMIT_LOC_STRINGS' => 'YES'
  )
  # .gitkeep holds empty Sources folders in git; it must not be bundled.
  # D20: fixtures never ship in a release build.
  s['EXCLUDED_SOURCE_FILE_NAMES'] = config.name == 'Release' ? '.gitkeep Fixtures.json' : '.gitkeep'
end

# The widget extension (TT-174, D67): the ride's Live Activity on the Lock Screen and in the Dynamic Island, and later the
# widgets (TT-181 onward). Embedded in the app; its version follows the app's, as App Store Connect requires.
widgets = project.new_target(:app_extension, 'TrainTimesWidgets', :ios, DEPLOYMENT_TARGET, nil, :swift)
widgets.file_system_synchronized_groups << widgets_dir << shared
widgets.build_configurations.each do |config|
  s = config.build_settings
  s.delete('INFOPLIST_FILE')
  s.merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.Widgets",
    'MARKETING_VERSION' => MARKETING_VERSION,
    'CURRENT_PROJECT_VERSION' => '1',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    # NSExtensionPointIdentifier com.apple.widgetkit-extension; Xcode merges the generated keys into it.
    'INFOPLIST_FILE' => 'Config/Widgets-Info.plist',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Train Times',
    'TARGETED_DEVICE_FAMILY' => '1',
    'CODE_SIGN_STYLE' => 'Automatic',
    'PROVISIONING_PROFILE_SPECIFIER' => '$(TT_WIDGETS_PROFILE)',
    'SKIP_INSTALL' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
    'SWIFT_EMIT_LOC_STRINGS' => 'YES',
    'EXCLUDED_SOURCE_FILE_NAMES' => '.gitkeep'
  )
end
app.add_dependency(widgets)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widgets.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Unit tests (hosted in the app, so Bundle.main is the app bundle).
unit = project.new_target(:unit_test_bundle, 'TrainTimesTests', :ios, DEPLOYMENT_TARGET, nil, :swift)
unit.file_system_synchronized_groups << unit_tests_dir << preview
unit.add_dependency(app)
unit.build_configurations.each do |config|
  config.build_settings.delete('INFOPLIST_FILE')
  config.build_settings.merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.Tests",
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/TrainTimes.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/TrainTimes',
    'CODE_SIGN_STYLE' => 'Automatic',
    'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '1.0',
    # Snapshot references are read from the source tree (#filePath). Bundling them would copy every
    # __Snapshots__/<Class>/<test>.1.png flat into the bundle, and two classes with the same test name collide.
    'EXCLUDED_SOURCE_FILE_NAMES' => '.gitkeep *.png'
  )
end

# UI tests.
ui = project.new_target(:ui_test_bundle, 'TrainTimesUITests', :ios, DEPLOYMENT_TARGET, nil, :swift)
ui.file_system_synchronized_groups << ui_tests_dir
ui.add_dependency(app)
ui.build_configurations.each do |config|
  config.build_settings.delete('INFOPLIST_FILE')
  config.build_settings.merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{BUNDLE_ID}.UITests",
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_TARGET_NAME' => 'TrainTimes',
    'CODE_SIGN_STYLE' => 'Automatic',
    'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '1.0'
  )
end

project.root_object.attributes['TargetAttributes'] = {
  app.uuid => { 'CreatedOnToolsVersion' => '16.0' },
  widgets.uuid => { 'CreatedOnToolsVersion' => '16.0' },
  unit.uuid => { 'CreatedOnToolsVersion' => '16.0', 'TestTargetID' => app.uuid },
  ui.uuid => { 'CreatedOnToolsVersion' => '16.0', 'TestTargetID' => app.uuid }
}

# swift-snapshot-testing, test-only (D6).
package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package.repositoryURL = 'https://github.com/pointfreeco/swift-snapshot-testing'
package.requirement = { 'kind' => 'exactVersion', 'version' => SNAPSHOT_TESTING_VERSION }
project.root_object.package_references << package

product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package
product.product_name = 'SnapshotTesting'
unit.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
unit.frameworks_build_phase.files << build_file

# new_target links Foundation.framework from a pinned SDK path; SwiftUI apps import it implicitly.
[app, widgets, unit, ui].each do |target|
  target.frameworks_build_phase.files.select { |f| f.display_name == 'Foundation.framework' }.each(&:remove_from_project)
end
project.frameworks_group.recursive_children.select { |c| c.display_name == 'Foundation.framework' }.each(&:remove_from_project)
project.frameworks_group.children.select { |g| g.children.empty? }.each(&:remove_from_project)
project.frameworks_group.remove_from_project

# Products group last, like Xcode does.
project.main_group.children.delete(project.products_group)
project.main_group.children << project.products_group

# Stable object ids, so regenerating the project produces a readable diff. An object's id comes from the first path
# that reaches it, and each pass hashes target dependencies with the ids the previous pass gave. The widget extension
# (TT-174) goes first while the ids are made: reached through the app, its id would hang on the app's, which hangs on
# its own, and never settle. Three passes for the chain unit tests → app → extension, then the usual order back.
project.targets.delete(widgets)
project.targets.unshift(widgets)
3.times { project.predictabilize_uuids }
project.targets.delete(widgets)
project.targets.insert(1, widgets)
project.save

# Shared scheme: build the app, run both test bundles.
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, unit)
scheme.test_action.add_testable(Xcodeproj::XCScheme::TestAction::TestableReference.new(ui))
scheme.launch_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(app, 0)
scheme.profile_action.buildable_product_runnable = Xcodeproj::XCScheme::BuildableProductRunnable.new(app, 0)
scheme.launch_action.build_configuration = 'Debug'
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(PROJECT_PATH, 'TrainTimes', true)

puts "Wrote #{PROJECT_PATH}"
