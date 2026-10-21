#!/usr/bin/env python3
"""Writes NewtonLibrary.xcodeproj/project.pbxproj (Xcode 13 format, so it opens in
Xcode 13 on macOS 12 and in every later Xcode). Add new source files to `groups`
below and run it again:

    python3 tools/make_project.py
"""
import itertools, os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
n=itertools.count(1)
def nid(): return 'B1%022X' % next(n)
groups={'NewtonLibrary':['NewtonLibraryApp.swift','Info.plist','Assets.xcassets'],
        'Package':['PackageInfo.swift','PackageReader.swift','MagicPointers.swift'],
        'Library':['LibraryDatabase.swift','LibraryItem.swift','LibraryStore.swift','Relations.swift'],
        'Views':['ContentView.swift','SidebarView.swift','PackageTable.swift','PackageDetailView.swift','PackageIcon.swift','PreferencesView.swift','InfoWindow.swift','TableDragSupport.swift','DebugSnapshot.swift']}
fref={}; bfile={}
for g,fs in groups.items():
    for f in fs:
        fref[f]=nid()
        if f!='Info.plist': bfile[f]=nid()
P=dict(project=nid(),main=nid(),products=nid(),app=nid(),target=nid(),src=nid(),res=nid(),frm=nid(),
       pcl=nid(),pdbg=nid(),prel=nid(),tcl=nid(),tdbg=nid(),trel=nid())
gid={g:nid() for g in groups}
def ftype(f):
    return {'swift':'sourcecode.swift','plist':'text.plist.xml','xcassets':'folder.assetcatalog'}[f.rsplit('.',1)[1]]
L=[]; w=L.append
w('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 55;\n\tobjects = {\n')
w('/* Begin PBXBuildFile section */')
for f,b in bfile.items():
    phase='Resources' if f.endswith('xcassets') else 'Sources'
    w('\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'%(b,f,phase,fref[f],f))
w('/* End PBXBuildFile section */\n')
w('/* Begin PBXFileReference section */')
w('\t\t%s /* Newton Library.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Newton Library.app"; sourceTree = BUILT_PRODUCTS_DIR; };'%P['app'])
for f,r in fref.items():
    w('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'%(r,f,ftype(f),f))
w('/* End PBXFileReference section */\n')
w('/* Begin PBXFrameworksBuildPhase section */\n\t\t%s /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXFrameworksBuildPhase section */\n'%P['frm'])
w('/* Begin PBXGroup section */')
w('\t\t%s = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* NewtonLibrary */,\n\t\t\t\t%s /* Products */,\n\t\t\t);\n\t\t\tsourceTree = "<group>";\n\t\t};'%(P['main'],gid['NewtonLibrary'],P['products']))
w('\t\t%s /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* Newton Library.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = "<group>";\n\t\t};'%(P['products'],P['app']))
for g,fs in groups.items():
    kids=[]
    if g=='NewtonLibrary':
        kids=['%s /* %s */'%(gid[x],x) for x in ('Package','Library','Views')]
    kids+=['%s /* %s */'%(fref[f],f) for f in fs]
    w('\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tpath = %s;\n\t\t\tsourceTree = "<group>";\n\t\t};'%(gid[g],g,'\n'.join('\t\t\t\t'+k+',' for k in kids),g))
w('/* End PBXGroup section */\n')
w('''/* Begin PBXNativeTarget section */
\t\t%(target)s /* NewtonLibrary */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = %(tcl)s /* Build configuration list for PBXNativeTarget "NewtonLibrary" */;
\t\t\tbuildPhases = (
\t\t\t\t%(src)s /* Sources */,
\t\t\t\t%(frm)s /* Frameworks */,
\t\t\t\t%(res)s /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = NewtonLibrary;
\t\t\tproductName = NewtonLibrary;
\t\t\tproductReference = %(app)s /* Newton Library.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t%(project)s /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1320;
\t\t\t\tLastUpgradeCheck = 1320;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t%(target)s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 13.2;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = %(pcl)s /* Build configuration list for PBXProject "NewtonLibrary" */;
\t\t\tcompatibilityVersion = "Xcode 13.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = %(main)s;
\t\t\tproductRefGroup = %(products)s /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t%(target)s /* NewtonLibrary */,
\t\t\t);
\t\t};
/* End PBXProject section */
'''%P)
w('/* Begin PBXResourcesBuildPhase section */\n\t\t%s /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t%s /* Assets.xcassets in Resources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXResourcesBuildPhase section */\n'%(P['res'],bfile['Assets.xcassets']))
w('/* Begin PBXSourcesBuildPhase section */\n\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXSourcesBuildPhase section */\n'%(P['src'],'\n'.join('\t\t\t\t%s /* %s in Sources */,'%(b,f) for f,b in bfile.items() if f.endswith('.swift'))))
common_proj='''\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 12.0;
\t\t\t\tSDKROOT = macosx;
'''
target_common='''\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = QCJDT3M7KP;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = NewtonLibrary/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Newton Library";
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "Written by Matt Hare and AI agent Claude";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 12.0;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = local.register.NewtonLibrary;
\t\t\t\tPRODUCT_NAME = "Newton Library";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
'''
def cfg(i,name,body): return '\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\t\t\t};\n\t\t\tname = %s;\n\t\t};'%(i,name,body,name)
w('/* Begin XCBuildConfiguration section */')
w(cfg(P['pdbg'],'Debug',common_proj+'''\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
'''))
w(cfg(P['prel'],'Release',common_proj+'''\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
'''))
w(cfg(P['tdbg'],'Debug',target_common))
w(cfg(P['trel'],'Release',target_common))
w('/* End XCBuildConfiguration section */\n')
w('/* Begin XCConfigurationList section */')
for lid,name,d,r in ((P['pcl'],'PBXProject "NewtonLibrary"',P['pdbg'],P['prel']),(P['tcl'],'PBXNativeTarget "NewtonLibrary"',P['tdbg'],P['trel'])):
    w('\t\t%s /* Build configuration list for %s */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};'%(lid,name,d,r))
w('/* End XCConfigurationList section */')
w('\t};\n\trootObject = %s /* Project object */;\n}'%P['project'])
open(os.path.join(ROOT,'NewtonLibrary.xcodeproj','project.pbxproj'),'w').write('\n'.join(L)+'\n')
print('wrote NewtonLibrary.xcodeproj/project.pbxproj')
