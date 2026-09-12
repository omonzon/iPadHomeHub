#!/usr/bin/env python3
"""Generates HomeHub.xcodeproj from the files on disk.

Hand-editing a .pbxproj is miserable and merge conflicts in one are worse, so
the project file is generated. Re-run this after adding or removing a source
file:

    python3 Scripts/generate_project.py                  # default build
    python3 Scripts/generate_project.py --homekit        # + HomeKit support
    python3 Scripts/generate_project.py --bundle-id com.you.homehub --team ABCDE12345

Requires nothing but Python 3 — no Xcode, no brew, no CocoaPods.
"""
import argparse
import hashlib
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = "HomeHub"
TARGET = "HomeHub"
DEPLOYMENT_TARGET = "15.0"   # oldest iPadOS an iPad Pro 12.9 (1st gen) can reach is 16.7


def uid(*parts):
    """Deterministic 24-hex object id, so regenerating produces a stable diff."""
    digest = hashlib.md5("|".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def quote(value):
    if value == "":
        return '""'
    safe = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./$")
    if all(character in safe for character in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % escaped


def settings_block(settings, indent):
    pad = "\t" * indent
    lines = []
    for key in sorted(settings):
        value = settings[key]
        if isinstance(value, list):
            lines.append("%s%s = (" % (pad, key))
            for item in value:
                lines.append("%s\t%s," % (pad, quote(item)))
            lines.append("%s);" % pad)
        else:
            lines.append("%s%s = %s;" % (pad, key, quote(value)))
    return "\n".join(lines)


def collect(directory, extensions):
    found = []
    for base, dirs, files in os.walk(os.path.join(ROOT, directory)):
        dirs[:] = [d for d in sorted(dirs) if not d.endswith(".xcassets")]
        for name in sorted(files):
            if os.path.splitext(name)[1] in extensions:
                found.append(os.path.relpath(os.path.join(base, name), ROOT))
    return found


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog",
}


def file_type(path):
    return FILE_TYPES.get(os.path.splitext(path)[1], "text")


class Project:
    def __init__(self, args):
        self.args = args
        self.sources = collect(APP_DIR, {".swift"})
        self.assets = os.path.join(APP_DIR, "Resources", "Assets.xcassets")
        self.info_plist = os.path.join(APP_DIR, "Resources", "Info.plist")
        self.entitlements = os.path.join(APP_DIR, "Resources", "HomeHub.entitlements")
        self.all_files = self.sources + [self.assets, self.info_plist, self.entitlements]

    # -- object ids -------------------------------------------------------

    def ref(self, path):
        return uid("fileRef", path)

    def build_file(self, path):
        return uid("buildFile", path)

    def group(self, path):
        return uid("group", path)

    # -- sections ---------------------------------------------------------

    def section_build_files(self):
        lines = ["/* Begin PBXBuildFile section */"]
        for path in self.sources + [self.assets]:
            name = os.path.basename(path)
            lines.append("\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                         % (self.build_file(path), name,
                            "Resources" if path == self.assets else "Sources",
                            self.ref(path), name))
        lines.append("/* End PBXBuildFile section */")
        return "\n".join(lines)

    def section_file_refs(self):
        lines = ["/* Begin PBXFileReference section */"]
        product = uid("product", TARGET)
        lines.append('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; '
                     'includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };'
                     % (product, TARGET, TARGET))
        for path in self.all_files:
            name = os.path.basename(path)
            lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
                         % (self.ref(path), name, file_type(path), quote(name)))
        lines.append("/* End PBXFileReference section */")
        return "\n".join(lines)

    def build_group_tree(self):
        """Mirrors the folder layout as Xcode groups."""
        tree = {}
        for path in self.all_files:
            parts = path.split(os.sep)
            node = tree
            for part in parts[:-1]:
                node = node.setdefault(part, {})
            node.setdefault("__files__", []).append(path)
        return tree

    def render_group(self, name, node, path, lines):
        children = []
        for key in sorted(k for k in node if k != "__files__"):
            child_path = os.path.join(path, key) if path else key
            children.append((self.group(child_path), key))
            self.render_group(key, node[key], child_path, lines)
        for file_path in sorted(node.get("__files__", [])):
            children.append((self.ref(file_path), os.path.basename(file_path)))

        body = "\n".join("\t\t\t\t%s /* %s */," % (identifier, label) for identifier, label in children)
        lines.append("\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tpath = %s;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                     % (self.group(path), name, body, quote(name)))

    def section_groups(self):
        tree = self.build_group_tree()
        lines = ["/* Begin PBXGroup section */"]

        main_group = uid("group", "__main__")
        products_group = uid("group", "__products__")
        product = uid("product", TARGET)

        top_children = []
        for key in sorted(k for k in tree if k != "__files__"):
            top_children.append((self.group(key), key))
            self.render_group(key, tree[key], key, lines)
        top_children.append((products_group, "Products"))

        body = "\n".join("\t\t\t\t%s /* %s */," % (identifier, label) for identifier, label in top_children)
        lines.append("\t\t%s = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                     % (main_group, body))
        lines.append("\t\t%s /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* %s.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                     % (products_group, product, TARGET))
        lines.append("/* End PBXGroup section */")
        return "\n".join(lines)

    def section_phases(self):
        sources_phase = uid("phase", "sources")
        frameworks_phase = uid("phase", "frameworks")
        resources_phase = uid("phase", "resources")

        source_entries = "\n".join(
            "\t\t\t\t%s /* %s in Sources */," % (self.build_file(path), os.path.basename(path))
            for path in self.sources)

        lines = [
            "/* Begin PBXFrameworksBuildPhase section */",
            "\t\t%s /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};" % frameworks_phase,
            "/* End PBXFrameworksBuildPhase section */",
            "",
            "/* Begin PBXResourcesBuildPhase section */",
            "\t\t%s /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t%s /* Assets.xcassets in Resources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
            % (resources_phase, self.build_file(self.assets)),
            "/* End PBXResourcesBuildPhase section */",
            "",
            "/* Begin PBXSourcesBuildPhase section */",
            "\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
            % (sources_phase, source_entries),
            "/* End PBXSourcesBuildPhase section */",
        ]
        return "\n".join(lines)

    def section_target_and_project(self):
        target = uid("target", TARGET)
        project = uid("project", TARGET)
        product = uid("product", TARGET)
        main_group = uid("group", "__main__")
        products_group = uid("group", "__products__")

        lines = [
            "/* Begin PBXNativeTarget section */",
            "\t\t%s /* %s */ = {\n"
            "\t\t\tisa = PBXNativeTarget;\n"
            "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"%s\" */;\n"
            "\t\t\tbuildPhases = (\n"
            "\t\t\t\t%s /* Sources */,\n"
            "\t\t\t\t%s /* Frameworks */,\n"
            "\t\t\t\t%s /* Resources */,\n"
            "\t\t\t);\n"
            "\t\t\tbuildRules = (\n\t\t\t);\n"
            "\t\t\tdependencies = (\n\t\t\t);\n"
            "\t\t\tname = %s;\n"
            "\t\t\tproductName = %s;\n"
            "\t\t\tproductReference = %s /* %s.app */;\n"
            "\t\t\tproductType = \"com.apple.product-type.application\";\n"
            "\t\t};" % (target, TARGET, uid("configlist", "target"), TARGET,
                        uid("phase", "sources"), uid("phase", "frameworks"),
                        uid("phase", "resources"), TARGET, TARGET, product, TARGET),
            "/* End PBXNativeTarget section */",
            "",
            "/* Begin PBXProject section */",
            "\t\t%s /* Project object */ = {\n"
            "\t\t\tisa = PBXProject;\n"
            "\t\t\tattributes = {\n"
            "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
            "\t\t\t\tLastSwiftUpdateCheck = 1500;\n"
            "\t\t\t\tLastUpgradeCheck = 1500;\n"
            "\t\t\t\tTargetAttributes = {\n"
            "\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t};\n"
            "\t\t\t\t};\n"
            "\t\t\t};\n"
            "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"%s\" */;\n"
            "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
            "\t\t\tdevelopmentRegion = en;\n"
            "\t\t\thasScannedForEncodings = 0;\n"
            "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
            "\t\t\tmainGroup = %s;\n"
            "\t\t\tproductRefGroup = %s /* Products */;\n"
            "\t\t\tprojectDirPath = \"\";\n"
            "\t\t\tprojectRoot = \"\";\n"
            "\t\t\ttargets = (\n\t\t\t\t%s /* %s */,\n\t\t\t);\n"
            "\t\t};" % (project, target, uid("configlist", "project"), TARGET,
                        main_group, products_group, target, TARGET),
            "/* End PBXProject section */",
        ]
        return "\n".join(lines)

    def project_settings(self, debug):
        settings = {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ANALYZER_NONNULL": "YES",
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
            "CLANG_WARN_UNREACHABLE_CODE": "YES",
            "COPY_PHASE_STRIP": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES",
            "GCC_NO_COMMON_BLOCKS": "YES",
            "GCC_WARN_UNDECLARED_SELECTOR": "YES",
            "GCC_WARN_UNUSED_FUNCTION": "YES",
            "GCC_WARN_UNUSED_VARIABLE": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
            "MTL_FAST_MATH": "YES",
            "SDKROOT": "iphoneos",
        }
        if debug:
            settings.update({
                "DEBUG_INFORMATION_FORMAT": "dwarf",
                "ENABLE_TESTABILITY": "YES",
                "GCC_DYNAMIC_NO_PIC": "NO",
                "GCC_OPTIMIZATION_LEVEL": "0",
                "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
                "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
                "ONLY_ACTIVE_ARCH": "YES",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": self.conditions("DEBUG"),
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            })
        else:
            settings.update({
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                "ENABLE_NS_ASSERTIONS": "NO",
                "MTL_ENABLE_DEBUG_INFO": "NO",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": self.conditions(""),
                "SWIFT_COMPILATION_MODE": "wholemodule",
                "SWIFT_OPTIMIZATION_LEVEL": "-O",
                "VALIDATE_PRODUCT": "YES",
            })
        return settings

    def conditions(self, base):
        flags = [flag for flag in [base, "HOMEHUB_HOMEKIT" if self.args.homekit else ""] if flag]
        return " ".join(flags)

    def target_settings(self, debug):
        settings = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": self.info_plist,
            "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": self.args.bundle_id,
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SUPPORTS_MACCATALYST": "NO",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": "1,2",
        }
        if self.args.team:
            settings["DEVELOPMENT_TEAM"] = self.args.team
        if self.args.homekit:
            settings["CODE_SIGN_ENTITLEMENTS"] = self.entitlements
        return settings

    def section_configurations(self):
        lines = ["/* Begin XCBuildConfiguration section */"]
        specs = [
            (uid("config", "project", "Debug"), "Debug", self.project_settings(True)),
            (uid("config", "project", "Release"), "Release", self.project_settings(False)),
            (uid("config", "target", "Debug"), "Debug", self.target_settings(True)),
            (uid("config", "target", "Release"), "Release", self.target_settings(False)),
        ]
        for identifier, name, settings in specs:
            lines.append("\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = %s;\n\t\t};"
                         % (identifier, name, settings_block(settings, 4), name))
        lines.append("/* End XCBuildConfiguration section */")
        lines.append("")
        lines.append("/* Begin XCConfigurationList section */")
        for scope, label in (("project", 'PBXProject "%s"' % TARGET),
                             ("target", 'PBXNativeTarget "%s"' % TARGET)):
            lines.append("\t\t%s /* Build configuration list for %s */ = {\n"
                         "\t\t\tisa = XCConfigurationList;\n"
                         "\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n"
                         "\t\t\tdefaultConfigurationIsVisible = 0;\n"
                         "\t\t\tdefaultConfigurationName = Release;\n\t\t};"
                         % (uid("configlist", scope), label,
                            uid("config", scope, "Debug"), uid("config", scope, "Release")))
        lines.append("/* End XCConfigurationList section */")
        return "\n".join(lines)

    def render(self):
        return "\n".join([
            "// !$*UTF8*$!",
            "{",
            "\tarchiveVersion = 1;",
            "\tclasses = {",
            "\t};",
            "\tobjectVersion = 56;",
            "\tobjects = {",
            "",
            self.section_build_files(),
            "",
            self.section_file_refs(),
            "",
            self.section_groups(),
            "",
            self.section_phases(),
            "",
            self.section_target_and_project(),
            "",
            self.section_configurations(),
            "",
            "\t};",
            "\trootObject = %s /* Project object */;" % uid("project", TARGET),
            "}",
            "",
        ])


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference
               BuildableIdentifier="primary"
               BlueprintIdentifier="{target}"
               BuildableName="{name}.app"
               BlueprintName="{name}"
               ReferencedContainer="container:{name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="{target}"
            BuildableName="{name}.app"
            BlueprintName="{name}"
            ReferencedContainer="container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="{target}"
            BuildableName="{name}.app"
            BlueprintName="{name}"
            ReferencedContainer="container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
   </ArchiveAction>
</Scheme>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bundle-id", default="com.example.homehub",
                        help="bundle identifier (must be unique to you)")
    parser.add_argument("--team", default="", help="Apple Developer Team ID")
    parser.add_argument("--homekit", action="store_true",
                        help="enable HomeKit (needs a paid Apple Developer account)")
    args = parser.parse_args()

    project = Project(args)
    bundle = os.path.join(ROOT, "%s.xcodeproj" % TARGET)
    if os.path.isdir(bundle):
        shutil.rmtree(bundle)
    schemes = os.path.join(bundle, "xcshareddata", "xcschemes")
    os.makedirs(schemes)

    with open(os.path.join(bundle, "project.pbxproj"), "w") as handle:
        handle.write(project.render())
    with open(os.path.join(schemes, "%s.xcscheme" % TARGET), "w") as handle:
        handle.write(SCHEME.format(target=uid("target", TARGET), name=TARGET))

    print("Generated %s.xcodeproj" % TARGET)
    print("  sources:   %d" % len(project.sources))
    print("  bundle id: %s" % args.bundle_id)
    print("  team:      %s" % (args.team or "(set it in Xcode > Signing & Capabilities)"))
    print("  HomeKit:   %s" % ("on" if args.homekit else "off"))


if __name__ == "__main__":
    main()
