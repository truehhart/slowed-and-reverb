#!/bin/sh
# Slowed and Reverb installer.
# curl -fsSL https://raw.githubusercontent.com/truehhart/slowed-and-reverb/master/install.sh | sh
#
# Downloads via curl on purpose: curl does NOT set the com.apple.quarantine flag,
# so the ad-hoc-signed app launches with no Gatekeeper "damaged"/"unidentified
# developer" prompt — the one free way to avoid that without Apple notarization.
set -eu

app="Slowed and Reverb.app"
dest="/Applications"
url="https://github.com/truehhart/slowed-and-reverb/releases/latest/download/slowed-and-reverb.app.tar.gz"

[ "$(uname -m)" = "arm64" ] || { echo "Apple Silicon (arm64) only." >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Slowed and Reverb…"
curl -fSL "$url" -o "$tmp/app.tar.gz"

echo "Installing to $dest/$app…"
rm -rf "$dest/$app"
tar xzf "$tmp/app.tar.gz" -C "$dest"

echo "Done. Launching…"
open "$dest/$app"
