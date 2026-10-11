#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; no XcodeGen or Ruby gems needed."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quoted(s): return json.dumps(str(s), ensure_ascii=False)

objects = []
def add(name, content):
    key = ident(name)
    objects.append(f"\t\t{key} = {{ {content} }};")
    return key
def array(items): return "(" + ", ".join(items) + ",)" if items else "()"
def config(name, values):
    settings = " ".join(f"{k} = {v};" for k, v in values.items())
    return add(name, f"isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {name.split('-')[-1]};")

app_sources = sorted((ROOT / "Sources/WayDetect").rglob("*.swift"))
ui_sources = sorted((ROOT / "UITests").glob("*.swift"))
def source_group(files, name):
    refs, builds = [], []
    for file in files:
        path = file.relative_to(ROOT).as_posix()
        ref = add(path, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
        refs.append(ref)
        builds.append(add(path + '-build', f"isa = PBXBuildFile; fileRef = {ref};"))
    group = add(name, f"isa = PBXGroup; children = {array(refs)}; name = {name}; sourceTree = \"<group>\";")
    return group, builds

app_group, app_builds = source_group(app_sources, 'App')
test_group, test_builds = source_group(ui_sources, 'UITests')
assets = add('Assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
assets_build = add('Assets-build', f'isa = PBXBuildFile; fileRef = {assets};')
app_product = add('WayDetect.app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = WayDetect.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('WayDetectUITests.xctest', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = WayDetectUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('Products', f'isa = PBXGroup; children = {array([app_product, test_product])}; name = Products; sourceTree = "<group>";')
root_group = add('Root', f'isa = PBXGroup; children = {array([app_group, test_group, assets, products])}; sourceTree = "<group>";')
package = add('CorePackage', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
package_product = add('CoreProduct', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = WayDetectCore;')
package_build = add('CoreBuild', f'isa = PBXBuildFile; productRef = {package_product};')

app_source_phase = add('AppSources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(app_builds)}; runOnlyForDeploymentPostprocessing = 0;')
app_resources = add('AppResources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array([assets_build])}; runOnlyForDeploymentPostprocessing = 0;')
app_frameworks = add('AppFrameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array([package_build])}; runOnlyForDeploymentPostprocessing = 0;')
test_source_phase = add('TestSources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(test_builds)}; runOnlyForDeploymentPostprocessing = 0;')
test_frameworks = add('TestFrameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')

project_configs, app_configs, test_configs = [], [], []
for mode in ['Debug', 'Release']:
    project_configs.append(config(f'Project-{mode}', {
        'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'SWIFT_VERSION': '5.0',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SDKROOT': 'iphoneos', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
        'SWIFT_OPTIMIZATION_LEVEL': quoted('-Onone' if mode == 'Debug' else '-O'),
        'DEBUG_INFORMATION_FORMAT': quoted('dwarf' if mode == 'Debug' else 'dwarf-with-dsym'),
        'ENABLE_TESTABILITY': 'YES' if mode == 'Debug' else 'NO',
        'ONLY_ACTIVE_ARCH': 'YES' if mode == 'Debug' else 'NO',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': quoted('DEBUG $(inherited)' if mode == 'Debug' else '$(inherited)')
    }))
    app_configs.append(config(f'App-{mode}', {
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.waydetect.prototype', 'PRODUCT_NAME': quoted('$(TARGET_NAME)'),
        'CODE_SIGN_STYLE': 'Automatic', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '1.0',
        'INFOPLIST_FILE': 'Resources/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO',
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
        'TARGETED_DEVICE_FAMILY': '1', 'SUPPORTED_PLATFORMS': quoted('iphoneos iphonesimulator'),
        'SUPPORTS_MACCATALYST': 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD': 'NO',
        'LD_RUNPATH_SEARCH_PATHS': quoted('$(inherited) @executable_path/Frameworks'), 'SWIFT_EMIT_LOC_STRINGS': 'YES'
    }))
    test_configs.append(config(f'Tests-{mode}', {
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.waydetect.prototype.UITests', 'PRODUCT_NAME': quoted('$(TARGET_NAME)'),
        'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'WayDetect',
        'TARGETED_DEVICE_FAMILY': '1', 'SUPPORTED_PLATFORMS': quoted('iphoneos iphonesimulator')
    }))
def config_list(name, refs): return add(name, f'isa = XCConfigurationList; buildConfigurations = {array(refs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project_config = config_list('ProjectConfig', project_configs)
app_config = config_list('AppConfig', app_configs)
test_config = config_list('TestConfig', test_configs)
app_target = add('AppTarget', f'isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = {array([app_source_phase, app_frameworks, app_resources])}; buildRules = (); dependencies = (); name = WayDetect; packageProductDependencies = {array([package_product])}; productName = WayDetect; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = add('AppProxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("Project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = WayDetect;')
dependency = add('TestDependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
test_target = add('TestTarget', f'isa = PBXNativeTarget; buildConfigurationList = {test_config}; buildPhases = {array([test_source_phase, test_frameworks])}; buildRules = (); dependencies = {array([dependency])}; name = WayDetectUITests; productName = WayDetectUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
project = add('Project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; BuildIndependentTargetsInParallel = 1; TargetAttributes = {{ {app_target} = {{ CreatedOnToolsVersion = 26.0; }}; {test_target} = {{ CreatedOnToolsVersion = 26.0; TestTargetID = {app_target}; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; hasScannedForEncodings = 0; knownRegions = (ko, en, Base); mainGroup = {root_group}; packageReferences = {array([package])}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app_target, test_target])};')
project_dir = ROOT / 'WayDetect.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {project};\n}}\n')
def buildable(target, name, product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:WayDetect.xcodeproj"/>'
app_ref = buildable(app_target, 'WayDetect', 'WayDetect.app')
test_ref = buildable(test_target, 'WayDetectUITests', 'WayDetectUITests.xctest')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project_dir / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / 'WayDetect.xcscheme').write_text(scheme)
info = {
    'CFBundleDevelopmentRegion': 'ko', 'CFBundleDisplayName': 'WayDetect', 'CFBundleExecutable': '$(EXECUTABLE_NAME)',
    'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': '$(PRODUCT_NAME)',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '$(MARKETING_VERSION)', 'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)',
    'LSRequiresIPhoneOS': True, 'NSMotionUsageDescription': '허리에 착용한 아이폰의 걸음과 회전을 측정하여 설정한 경로 순서와 방향을 안내합니다.',
    'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False}, 'UILaunchScreen': {},
    'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
    'UIRequiredDeviceCapabilities': ['arm64', 'gyroscope', 'accelerometer'],
    'ITSAppUsesNonExemptEncryption': False
}
(ROOT / 'Resources/Info.plist').write_bytes(plistlib.dumps(info))
(ROOT / 'Resources/Assets.xcassets/Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
(ROOT / 'Resources/Assets.xcassets/AccentColor.colorset/Contents.json').write_text(json.dumps({'colors': [{'idiom': 'universal', 'color': {'color-space': 'srgb', 'components': {'red': '0.31', 'green': '0.29', 'blue': '0.85', 'alpha': '1.0'}}}], 'info': {'author': 'xcode', 'version': 1}}))
(ROOT / 'Resources/Assets.xcassets/AppIcon.appiconset/Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}))
print(f'Generated {project_dir} ({len(app_sources)} app sources, {len(ui_sources)} UI test sources)')
