#!/usr/bin/env nu

let repo = ($env.FILE_PWD | path dirname)
let ytdlp = (mise which yt-dlp)
let out_dir = ($repo | path join "src-tauri" "binaries")
let out = ($out_dir | path join "yt-dlp")
let internal = ($ytdlp | path dirname | path join "_internal")

mkdir $out_dir
cp -f $ytdlp $out
cp -r -u $internal $out_dir
chmod +x $out

print $"bundled ($ytdlp) -> ($out)"
