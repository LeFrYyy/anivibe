#!/usr/bin/env python3
"""Генерирует Anivibe.xcodeproj (формат Xcode 16, objectVersion 77).

Исходники приложения подключаются через «синхронизированную папку» Anivibe/,
поэтому новые .swift-файлы попадают в сборку автоматически — перегенерация нужна
только при изменении настроек проекта. Запуск: python3 scripts/generate_xcodeproj.py
"""
import hashlib, os, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

def oid(name: str) -> str:
    return hashlib.md5(("anivibe:" + name).encode()).hexdigest()[:24].upper()

I = {k: oid(k) for k in [
    "project", "mainGroup", "productsGroup", "configGroup", "appSync", "appProduct",
    "xcconfig", "infoplist", "secretsExample", "target", "sources", "frameworks", "resources",
    "coreBuildFile", "coreProductDep", "localPkg",
    "projDebug", "projRelease", "projConfigList", "tgtDebug", "tgtRelease", "tgtConfigList",
]}

common_project = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
debug_project = dict(common_project, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"DEBUG $(inherited)\"",
    "SWIFT_OPTIMIZATION_LEVEL": "\"-Onone\"",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
})
release_project = dict(common_project, **{
    "DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\"",
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
    "MTL_ENABLE_DEBUG_INFO": "NO",
})
target_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Anivibe",
    "INFOPLIST_KEY_LSApplicationCategoryType": "\"public.app-category.entertainment\"",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "\"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\"",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": "(\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t\t\"@executable_path/Frameworks\",\n\t\t\t\t)",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SUPPORTED_PLATFORMS": "\"iphoneos iphonesimulator\"",
    "SUPPORTS_MACCATALYST": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}

def settings(d):
    return "".join(f"\t\t\t\t{k} = {v};\n" for k, v in sorted(d.items()))

def config(id_, name, d, base=None):
    b = f"\t\t\tbaseConfigurationReference = {I['xcconfig']} /* Anivibe.xcconfig */;\n" if base else ""
    return (f"\t\t{id_} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n{b}"
            f"\t\t\tbuildSettings = {{\n{settings(d)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['coreBuildFile']} /* AnivibeCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['coreProductDep']} /* AnivibeCore */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{I['appProduct']} /* Anivibe.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Anivibe.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['xcconfig']} /* Anivibe.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Anivibe.xcconfig; sourceTree = "<group>"; }};
		{I['secretsExample']} /* Secrets.example.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.example.xcconfig; sourceTree = "<group>"; }};
		{I['infoplist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['appSync']} /* Anivibe */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Anivibe;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['coreBuildFile']} /* AnivibeCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['appSync']} /* Anivibe */,
				{I['configGroup']} /* Config */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['configGroup']} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{I['xcconfig']} /* Anivibe.xcconfig */,
				{I['secretsExample']} /* Secrets.example.xcconfig */,
				{I['infoplist']} /* Info.plist */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['appProduct']} /* Anivibe.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['target']} /* Anivibe */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['tgtConfigList']} /* Build configuration list for PBXNativeTarget "Anivibe" */;
			buildPhases = (
				{I['sources']} /* Sources */,
				{I['frameworks']} /* Frameworks */,
				{I['resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['appSync']} /* Anivibe */,
			);
			name = Anivibe;
			packageProductDependencies = (
				{I['coreProductDep']} /* AnivibeCore */,
			);
			productName = Anivibe;
			productReference = {I['appProduct']} /* Anivibe.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{I['target']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {I['projConfigList']} /* Build configuration list for PBXProject "Anivibe" */;
			developmentRegion = ru;
			hasScannedForEncodings = 0;
			knownRegions = (
				ru,
				en,
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I['localPkg']} /* XCLocalSwiftPackageReference "Packages/AnivibeCore" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['target']} /* Anivibe */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{config(I['projDebug'], 'Debug', debug_project)}{config(I['projRelease'], 'Release', release_project)}{config(I['tgtDebug'], 'Debug', target_common, base=True)}{config(I['tgtRelease'], 'Release', target_common, base=True)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I['projConfigList']} /* Build configuration list for PBXProject "Anivibe" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['projDebug']} /* Debug */,
				{I['projRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['tgtConfigList']} /* Build configuration list for PBXNativeTarget "Anivibe" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['tgtDebug']} /* Debug */,
				{I['tgtRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I['localPkg']} /* XCLocalSwiftPackageReference "Packages/AnivibeCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/AnivibeCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I['coreProductDep']} /* AnivibeCore */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = AnivibeCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['target']}" BuildableName = "Anivibe.app" BlueprintName = "Anivibe" ReferencedContainer = "container:Anivibe.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "AnivibeCoreTests" BuildableName = "AnivibeCoreTests" BlueprintName = "AnivibeCoreTests" ReferencedContainer = "container:Packages/AnivibeCore">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['target']}" BuildableName = "Anivibe.app" BlueprintName = "Anivibe" ReferencedContainer = "container:Anivibe.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I['target']}" BuildableName = "Anivibe.app" BlueprintName = "Anivibe" ReferencedContainer = "container:Anivibe.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

proj = ROOT / "Anivibe.xcodeproj"
(proj / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
(proj / "project.pbxproj").write_text(pbx)
(proj / "xcshareddata" / "xcschemes" / "Anivibe.xcscheme").write_text(scheme)
ws = proj / "project.xcworkspace"
ws.mkdir(exist_ok=True)
(ws / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')
print("Generated", proj)
