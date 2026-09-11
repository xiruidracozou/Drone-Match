#!/usr/bin/env python3
"""Generate the dependency-free Xcode project from the tracked Swift files."""
from pathlib import Path
import hashlib
import plistlib

root = Path(__file__).resolve().parents[1] / 'apps/ios'
project = root / 'DroneMatch.xcodeproj'
project.mkdir(exist_ok=True)
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def quoted(value): return '"' + value.replace('\\','\\\\').replace('"','\\"') + '"'
objects=[]
def add(key, content): objects.append(f'{uid(key)} = {{ {content} }};')
files=sorted((root/'DroneMatch').glob('*.swift'))
for file in files:
    add('file:'+file.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(file.name)}; sourceTree = "<group>";')
    add('build:'+file.name, f'isa = PBXBuildFile; fileRef = {uid("file:"+file.name)};')
add('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(uid('build:'+f.name) for f in files) + '); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add('media', 'isa = PBXFileReference; lastKnownFileType = folder; path = Media; sourceTree = \"<group>\";')
add('mediaBuild', f'isa = PBXBuildFile; fileRef = {uid("media")};')
add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("mediaBuild")}); runOnlyForDeploymentPostprocessing = 0;')
add('app','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DroneMatch.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('sourceGroup', 'isa = PBXGroup; children = (' + ','.join([uid('file:'+f.name) for f in files]+[uid('media')]) + '); path = DroneMatch; sourceTree = "<group>";')
add('products',f'isa = PBXGroup; children = ({uid("app")}); name = Products; sourceTree = "<group>";')
add('root',f'isa = PBXGroup; children = ({uid("sourceGroup")},{uid("products")}); sourceTree = "<group>";')
for config in ['Debug','Release']:
    add('project'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; SWIFT_OPTIMIZATION_LEVEL = {quoted("-Onone" if config=="Debug" else "-O")}; }};')
    add('target'+config, f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
      PRODUCT_BUNDLE_IDENTIFIER = com.dronematch.local; PRODUCT_NAME = "$(TARGET_NAME)";
      INFOPLIST_FILE = DroneMatch/Info.plist; GENERATE_INFOPLIST_FILE = NO;
      TARGETED_DEVICE_FAMILY = "1,2"; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0;
      CODE_SIGN_STYLE = Automatic; SWIFT_EMIT_LOC_STRINGS = YES;
      "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = DroneMatch/Simulator.entitlements;
      SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
      ENABLE_USER_SCRIPT_SANDBOXING = YES;
      SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quoted('DEBUG' if config=='Debug' else '')};
    }};''')
for kind in ['project','target']:
    add(kind+'List',f'isa = XCConfigurationList; buildConfigurations = ({uid(kind+"Debug")},{uid(kind+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetList")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = DroneMatch; productName = DroneMatch; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {uid("projectList")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en,"zh-Hans",Base); mainGroup = {uid("root")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
schemes=project/'xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="DroneMatch.app" BlueprintName="DroneMatch" ReferencedContainer="container:DroneMatch.xcodeproj"/>'
(schemes/'DroneMatch.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
info={'CFBundleDevelopmentRegion':'zh_CN','CFBundleDisplayName':'无人机足球','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'APIBaseURL':'http://127.0.0.1:3001/api/v1','NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}
info['NSLocationWhenInUseUsageDescription'] = '用于识别当前城市，帮助你查找当地的无人机足球赛事和俱乐部。也可以不授权并手动选择城市。'
(root/'DroneMatch/Info.plist').write_bytes(plistlib.dumps(info))
print(project)
