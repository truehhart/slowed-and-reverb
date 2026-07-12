#!/bin/sh
# Slowed and Reverb installer.
# curl -fsSL https://raw.githubusercontent.com/truehhart/slowed-and-reverb/master/install.sh | sh
#
# Downloads via curl on purpose: curl does NOT set the com.apple.quarantine flag,
# so the ad-hoc-signed app launches with no Gatekeeper "damaged"/"unidentified
# developer" prompt: the one free way to avoid that without Apple notarization.
set -eu

app="Slowed and Reverb.app"
dest="/Applications"
# The .dmg is the durable release asset (also used by Sparkle updates and the
# Homebrew cask); name has no version so latest/download stays stable.
url="https://github.com/truehhart/slowed-and-reverb/releases/latest/download/Slowed.and.Reverb_aarch64.dmg"

[ "$(uname -m)" = "arm64" ] || { echo "Apple Silicon (arm64) only." >&2; exit 1; }

tmp="$(mktemp -d)"
mnt="$tmp/mnt"
mkdir -p "$mnt"
trap 'hdiutil detach "$mnt" -quiet 2>/dev/null; rm -rf "$tmp"' EXIT

echo "Downloading Slowed and Reverb…"
curl -fSL "$url" -o "$tmp/app.dmg"

hdiutil attach "$tmp/app.dmg" -nobrowse -readonly -mountpoint "$mnt" >/dev/null

echo "Installing to $dest/$app…"
rm -rf "${dest:?}/${app:?}"
cp -R "$mnt/$app" "$dest/$app"

hdiutil detach "$mnt" -quiet

echo "Done. Launching…"
open "$dest/$app"
