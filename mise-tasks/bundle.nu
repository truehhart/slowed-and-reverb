#!/usr/bin/env nu

# Assembles "Slowed and Reverb.app" from a `swift build` output: binary,
# Info.plist (version + Sparkle key stamped in), icon, bundled yt-dlp,
# and Sparkle.framework with an ad-hoc signature.

def main [
  config: string = "release" # swift build configuration: debug or release
] {
  let repo = ($env.FILE_PWD | path dirname)
  let version = (open ($repo | path join "VERSION") | str trim)
  let app_path = ($repo | path join ".build" "bundle" $config "Slowed and Reverb.app")
  let contents = ($app_path | path join "Contents")
  let macos_dir = ($contents | path join "MacOS")
  let resources_dir = ($contents | path join "Resources")
  let frameworks_dir = ($contents | path join "Frameworks")

  print $"Building SlowedAndReverb \(($config)\)..."
  mise exec -- swift build -c $config --package-path $repo

  let bin_dir = (mise exec -- swift build -c $config --show-bin-path --package-path $repo | str trim)
  let built_bin = ($bin_dir | path join "SlowedAndReverb")

  rm -rf $app_path
  mkdir $macos_dir
  mkdir $resources_dir
  mkdir $frameworks_dir

  let target_bin = ($macos_dir | path join "SlowedAndReverb")
  cp $built_bin $target_bin

  # SPM resource bundle (UI fonts + brand logo); Bundle.module resolves it
  # from Contents/Resources in the packaged app.
  let resource_bundle = ($bin_dir | path join "SlowedAndReverb_SlowedAndReverb.bundle")
  if not ($resource_bundle | path exists) {
    error make {msg: $"SPM resource bundle not found at ($resource_bundle)"}
  }
  ^ditto $resource_bundle ($resources_dir | path join "SlowedAndReverb_SlowedAndReverb.bundle")

  let sparkle_key = ($env.SPARKLE_PUBLIC_ED_KEY? | default "")
  if ($sparkle_key | is-empty) {
    print "warning: SPARKLE_PUBLIC_ED_KEY is unset; bundling with an empty SUPublicEDKey, Sparkle will not verify update signatures"
  }
  let plist = ($contents | path join "Info.plist")
  cp ($repo | path join "packaging" "Info.plist.template") $plist
  ^/usr/libexec/PlistBuddy -c $"Set :CFBundleShortVersionString ($version)" $plist
  ^/usr/libexec/PlistBuddy -c $"Set :CFBundleVersion ($version)" $plist
  if ($sparkle_key | is-not-empty) {
    ^/usr/libexec/PlistBuddy -c $"Set :SUPublicEDKey ($sparkle_key)" $plist
  }
  ^plutil -lint -s $plist

  cp ($repo | path join "packaging" "icon.icns") ($resources_dir | path join "icon.icns")

  # PATH is a dev-only fallback; the packaged app always uses this bundled copy.
  # yt-dlp (mise) is a PyInstaller onedir build: the launcher loads its Python
  # runtime from a sibling `_internal/`, so both must land in Resources.
  let ytdlp = (mise which yt-dlp | str trim)
  if ($ytdlp | is-empty) {
    error make {msg: "yt-dlp not found (run `mise install`)"}
  }
  cp $ytdlp ($resources_dir | path join "yt-dlp")
  chmod +x ($resources_dir | path join "yt-dlp")
  let ytdlp_internal = ($ytdlp | path dirname | path join "_internal")
  if not ($ytdlp_internal | path exists) {
    error make {msg: $"yt-dlp _internal not found next to ($ytdlp)"}
  }
  ^ditto $ytdlp_internal ($resources_dir | path join "_internal")

  let sparkle_matches = (glob ($repo | path join ".build" "artifacts" "sparkle" "**" "macos-arm64_x86_64" "Sparkle.framework"))
  if ($sparkle_matches | is-empty) {
    error make {msg: "Sparkle.framework artifact not found under .build/artifacts/sparkle (run `mise exec -- swift build` first)"}
  }
  let sparkle_src = ($sparkle_matches | first)
  let sparkle_dst = ($frameworks_dir | path join "Sparkle.framework")
  # ditto, not cp -r: preserves the framework's internal Versions/Current symlinks.
  ^ditto $sparkle_src $sparkle_dst

  let rpath_present = (^otool -l $target_bin | str contains "@executable_path/../Frameworks")
  if not $rpath_present {
    ^install_name_tool -add_rpath "@executable_path/../Frameworks" $target_bin
  }

  # Ad-hoc sign inside-out: Sparkle's XPC helpers and Autoupdate tool first,
  # then the framework, then the app bundle as a whole.
  for xpc in (glob ($sparkle_dst | path join "XPCServices" "*.xpc")) {
    ^codesign --force -s - $xpc
  }
  ^codesign --force -s - ($sparkle_dst | path join "Autoupdate")
  ^codesign --force -s - ($sparkle_dst | path join "Updater.app")
  ^codesign --force -s - $sparkle_dst
  ^codesign --force -s - --deep $app_path

  print $"bundled -> ($app_path)"
  $app_path
}
