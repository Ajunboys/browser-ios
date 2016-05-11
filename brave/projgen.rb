#!/usr/bin/env ruby
require 'xcodeproj'
require "pathname"

$target_hash = {}
$hash_file_to_target = {}
$client_resources = []
fabric_keys = []

system('cd ..; rm -rf Client.xcodeproj; tar xzf Client.xcodeproj.tgz')
begin
  fabric_keys = File.readlines(File.expand_path('~/.brave-fabric-keys'))
  system("sed -e 's/FABRIC_KEY_REMOVED/" + fabric_keys[0].strip + "/' BraveInfo.plist.template > BraveInfo.plist")
  system("> xcconfig/.local-def.xcconfig")
rescue SystemCallError
  puts 'No Fabric'
  system("\\cp -f BraveInfo.plist.template BraveInfo.plist")
  system("echo 'LOCAL_DEF_OTHER_SWIFT_FLAGS = -DNO_FABRIC' > xcconfig/.local-def.xcconfig")
end

if ARGV[0] == 'flex'
  system("echo 'LOCAL_DEF_OTHER_SWIFT_FLAGS = -DFLEX_ON\nLOCAL_DEF_GCC_PREPROCESSOR_DEFINITIONS = FLEX_ON=1\n' >> xcconfig/.local-def.xcconfig")
end

bundle_id = File.readlines('xcconfig/.bundle-id.xcconfig')[0].strip.delete(' ').delete('CUSTOM_BUNDLE_ID=')
system("sed -i '' -e 's/BUNDLE-ID-PLACEHOLDER/" + bundle_id + "/' BraveInfo.plist")

# Open the existing Xcode project
project_file = '../Client.xcodeproj'
project = Xcodeproj::Project.open(project_file)

for t in project.targets
  $target_hash[t.name] = {'target' => t, 'files' => []}
end

if fabric_keys.count == 2
  $target_hash['Client']['target'].new_shell_script_build_phase("Fabric key setup").shell_script =
      './Fabric.framework/run $(head -1 ~/.brave-fabric-keys) $(tail -1 ~/.brave-fabric-keys)'
end

# add recursively groups and files
def walk(proj, base, start, override_target = nil)
  folder = start[base.length + 1,start.length]
  Dir.foreach(start) do |x|
    path = File.join(start, x)
    if x == "." or x == ".." or x == ".DS_Store" or x == 'sqlcipher' or x == 'SQLite.swift'
      next
    elsif File.directory?(path)
      if path =~ /(\.xcasset)|(SearchPlugins)/
        file_ref = proj.new_file(path)
        $client_resources.push(file_ref)
      else
        folder = folder.gsub('./','')
        proj[folder].new_group(x)
        walk(proj, base, path, override_target)
      end
    else
      folder = folder.gsub('./','')
      file_ref = proj[folder].new_file(path)
      if path =~ /(\.js)|(\.html)|(\.txt)|(\.xib)|(\.dat)/
        $client_resources.push(file_ref)
      else
        # file was added to xcode file listing, if an optional target is set, it gets added to a build target
        path = path.sub('./', '')
        tname = override_target.nil? ? $hash_file_to_target[path] : override_target
        if tname != nil
          $target_hash[tname]['files'].push(file_ref)
        end
      end
    end
  end
end

# add all files to project
def addFiles(proj, base, folder)
  proj.new_group(folder)
  walk(proj, base, File.join(base, folder))
end

# read list of files per target into hash
# target[filename] returns the target for it or nil
def addBuildFiles(proj, target, file)
   for i in File.readlines(file)
     $hash_file_to_target[i.strip] = target
   end
end

for target in ['Account', 'BraveShareTo', 'Client', 'ReadingList', 'Shared', 'Storage', 'Sync']
    addBuildFiles(project, target, 'build-system/target-' + target + '.txt')
end

Dir.chdir('..')

###################################

brave = project.new_group('brave')

if ARGV[0] == 'flex'
    brave.new_group('ThirdParty')
    walk(project, '.', './brave/ThirdParty', 'Client')
end

entitlements = brave.new_file('brave/Brave.entitlements')
brave.new_file('brave/BraveInfo.plist')
$client_resources.push(entitlements)

$target_hash['BraveShareTo']['target'].add_resources([entitlements])

brave = brave.new_group('src')
walk(project, '.', './brave/src', 'Client')

abp_group = brave.new_group('abp-filter-parser-cpp', 'brave/node_modules/abp-filter-parser-cpp')
for f in ['ABPFilterParser.h', 'ABPFilterParser.cpp', 'filter.cpp',
          'node_modules/bloom-filter-cpp/BloomFilter.cpp', 'node_modules/bloom-filter-cpp/BloomFilter.h',
          'node_modules/hashset-cpp/hashFn.h', 'node_modules/hashset-cpp/HashItem.h',
          'node_modules/hashset-cpp/HashSet.h', 'node_modules/hashset-cpp/HashSet.cpp',
          'cosmeticFilter.h', 'cosmeticFilter.cpp']
  file_ref = abp_group.new_file(f)
  $target_hash['Client']['files'].push(file_ref)
end

tp_group = brave.new_group('tracking-protection', 'brave/node_modules/tracking-protection')
for f in ['FirstPartyHost.h', 'TPParser.h', 'TPParser.cpp']
  file_ref = tp_group.new_file(f)
  $target_hash['Client']['files'].push(file_ref)
end

if fabric_keys.count == 2
  for f in ['Fabric.framework', 'Crashlytics.framework']
    ref = project.frameworks_group.new_file(f)
    # @type PBXFrameworksBuildPhase
    phase = $target_hash['Client']['target'].frameworks_build_phase
    phase.add_file_reference(ref)
  end
end

##################################

for f in ['Account', 'BraveShareTo', 'Client', 'Extensions', 'FxA', 'FxAClient',
          'Providers', 'ReadingList', 'Shared', 'Storage', 'Sync', 'ThirdParty', 'Utils']
  addFiles(project, '.', f)
end

$target_hash.each do |key, val|
  val['target'].add_file_references(val['files'])
end

$target_hash['Client']['target'].add_resources($client_resources)

project.save
system("cd Client.xcodeproj && sed -i '' -e 's/com.brave.ios.browser/" + bundle_id + "/' project.pbxproj")

exit
