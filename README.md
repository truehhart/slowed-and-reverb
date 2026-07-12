<h1 align="center">slowed + reverb</h1>

<p align="center"><i>"Literally everything sounds better Slowed and Reverb."</i> (c) Me</p>

<p align="center">
  <a href="https://github.com/truehhart/slowed-and-reverb/releases"><img src="https://img.shields.io/github/v/release/truehhart/slowed-and-reverb?sort=semver" alt="release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="license" /></a>
</p>

---

A native macOS app that plays YouTube audio **slowed down and with reverb**. Paste a video or playlist URL; it resolves and downloads a pre-encoded audio stream with [yt-dlp](https://github.com/yt-dlp/yt-dlp) and plays it back through AVFoundation. Slowing the track also drops its pitch, which is exactly the slowed aesthetic.

## Features

- **Video or playlist** — paste either; playlists queue up and auto-advance.
- **Speed** — slows the track and drops the pitch with it, the classic slowed sound.
- **Reverb** — wet amount, a room/hall/plate space, and a low cut to keep the tail clean.
- **Live queue** — add and import tracks on the fly.
- **Feels native on macOS** — media keys and the OS Now Playing controls just work.
- **Smart caching** — downloaded audio is cached for instant replays.
- **Self-contained** — `yt-dlp` ships inside the app; nothing else to install.

## Install

macOS on Apple Silicon (arm64) only.

**Homebrew** (recommended):

```sh
brew install --cask truehhart/tap/slowed-and-reverb
```

**One-line install** (no Homebrew):

```sh
curl -fsSL https://raw.githubusercontent.com/truehhart/slowed-and-reverb/master/install.sh | sh
```

<details>
<summary><b>Manual <code>.dmg</code> install</b></summary>

Grab the `.dmg` from the [latest release](https://github.com/truehhart/slowed-and-reverb/releases), open it, and drag the app into **Applications**.

Builds aren't notarized, so a browser-downloaded `.dmg` is flagged by Gatekeeper and the app won't open. Clear the flag once:

```sh
xattr -dr com.apple.quarantine "/Applications/Slowed and Reverb.app"
```

</details>

## Develop

The app is a Swift Package Manager executable (no Xcode project). [mise](https://mise.jdx.dev) pins the whole toolchain (Swift, yt-dlp, Nushell).

```sh
mise install      # install the toolchain
mise run dev      # swift run, unbundled, for fast iteration
mise run test     # Swift Testing suite
mise run check    # pre-commit gate: swift build + swift-format lint + file-structure guard
mise run build    # assemble the .app bundle (Sparkle + bundled yt-dlp)
```

Always go through **mise** — never call raw `swift`/`swift-format`. Other tasks: `mise run fmt`, `mise run lint`.

## Release

`VERSION` is the single checked-in release version. Cut a release by dispatching the **`release`** GitHub Actions workflow: it reads `VERSION`, fails if the `v<version>` tag or release already exists, runs `check`, and pushes the tag. That tag triggers **`publish`**, which builds the `.app`, packages a `.dmg`, generates a Sparkle-signed appcast, publishes the GitHub release, and pushes an updated Homebrew cask to `truehhart/homebrew-tap`. Builds are arm64-only and unsigned by Apple (ad-hoc signed, Sparkle-signed for updates).
