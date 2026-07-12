# CLAUDE.md — slowed-and-reverb

`slowed-and-reverb` is a native **macOS Swift** app that plays YouTube audio **slowed and reverbed**. Paste a video or playlist URL; an `actor YtDlpClient` resolves and downloads a pre-encoded audio stream with **yt-dlp**, and playback runs through **AVFoundation** (`AVAudioEngine`): varispeed/time-pitch for the slow (which also drops pitch, exactly the slowed aesthetic) and `AVAudioUnitReverb` for reverb.

It is a **Swift Package Manager executable** — no Xcode project, no `.xcodeproj`, no `xcodebuild`. The SwiftUI UI layer is currently a placeholder window; a full UI redesign is pending (see `docs/design/`, which are reference artifacts, not the current UI).

## Hard rules

- **`actor YtDlpClient` owns all I/O.** yt-dlp invocation, the network, temp files, and the audio cache live in `Sources/SlowedAndReverb/Core/YtDlpClient.swift`. Keep process/filesystem/network I/O out of the UI and models.
- **No `-x`/`--extract-audio`** in yt-dlp calls — it pulls in ffmpeg. Download a pre-encoded audio stream (`bestaudio[ext=m4a]/bestaudio`) instead.
- **Surface yt-dlp stderr** in errors so failures are debuggable.
- yt-dlp is **bundled** into the `.app` (`packaging/`, `bundle.nu`). The packaged app always uses the bundled copy; PATH is only a dev/build-time fallback.
- **mise tasks are the only entry points** — never call raw `swift` / `swift-format`. Standalone scripts go in `mise-tasks/` and are **Nushell** (`#!/usr/bin/env nu`).
- **Swift Testing, not XCTest** — use `import Testing` (`@Test`, `#expect`). Tests live in `Tests/SlowedAndReverbTests`.
- **One non-private top-level type per file**, named after the file. `mise run check` enforces this (`mise-tasks/check-file-structure.nu`).
- **swift-format strict** — `mise run check` runs `swift format lint --strict`; warnings are errors.
- **Default `MainActor` isolation** — the package sets `.defaultIsolation(MainActor.self)`; types are main-actor unless explicitly `nonisolated` or their own actor.
- **Conventional Commits**; **never commit without operator review**.
- **Check libraries before inventing** audio/DSP, complex UI, gestures, sliders, visualization, or layout-heavy interaction. Prefer a small, well-maintained library that fits macOS/SwiftUI when it handles hard domain behavior better than local code; implement locally only when the feature is tiny, stable, and cheaper than the dependency.

## Commands (via mise — always use these)

| Command          | What                                                                     |
| ---------------- | ------------------------------------------------------------------------ |
| `mise install`   | install toolchain (swift, yt-dlp, nushell)                               |
| `mise run dev`   | Run unbundled; rebuild and restart when Swift sources change              |
| `mise run build` | assemble the `.app` bundle (`mise-tasks/bundle.nu`)                       |
| `mise run check` | pre-commit gate: `swift build` + swift-format lint + file-structure guard |
| `mise run test`  | Swift Testing suite                                                      |
| `mise run fmt`   | `swift format --in-place` over `Sources` and `Tests`                     |
| `mise run lint`  | `swift format lint --strict`                                             |

## Layout

| Path                                    | Purpose                                                        |
| --------------------------------------- | -------------------------------------------------------------- |
| `Package.swift`                         | SPM manifest (executable + test target, Sparkle dependency)    |
| `Sources/SlowedAndReverb/SlowedAndReverbApp.swift` | `@main` SwiftUI app shell (placeholder window)      |
| `Sources/SlowedAndReverb/Core/`         | models and I/O: `PlayerModel`, `YtDlpClient` (actor), `AVFoundationAudioEngine`, `URLParsing`, `UpdaterModel`, `NowPlayingController`, ... |
| `Tests/SlowedAndReverbTests/`           | Swift Testing tests + fakes under `Support/`                   |
| `mise-tasks/bundle.nu`                  | assemble the `.app`: binary, Info.plist, icon, yt-dlp, Sparkle |
| `mise-tasks/check-file-structure.nu`    | one-type-per-file guard                                        |
| `packaging/`                            | `Info.plist.template`, `icon.icns`                             |
| `.github/workflows/`                    | `check`, `release`, `publish` (see `.github/CLAUDE.md`)        |

## Distribution

`VERSION` is the single checked-in release version. Releases are cut by dispatching the **`release`** workflow; it reads `VERSION`, fails if the `v<version>` tag or GitHub release already exists, runs `check`, and pushes the tag. That tag triggers **`publish`**, which builds the `.app` via `bundle.nu` (Info.plist stamped with `VERSION` + the Sparkle public key, bundled yt-dlp, `Sparkle.framework`, ad-hoc codesign), packages a `.dmg`, generates a Sparkle-signed `appcast.xml`, publishes the GitHub release, and pushes a Homebrew cask to `truehhart/homebrew-tap` (`brew install --cask truehhart/tap/slowed-and-reverb`). Builds are **arm64-only** (yt-dlp is an arch-specific bundled resource) and **unsigned** by Apple (ad-hoc only); the cask strips quarantine in `postflight`, and a manual `.dmg`/`.app` install needs `xattr -dr com.apple.quarantine <app>`. Updates run through **Sparkle**: `SPARKLE_PUBLIC_ED_KEY` is baked into Info.plist and `SPARKLE_ED_PRIVATE_KEY` signs the appcast — do not rotate or lose the keypair unless intentionally breaking updates for installed apps. Apple signing/notarization (`APPLE_*` secrets) is a documented later add. See `.github/CLAUDE.md` for the GitHub Actions conventions.
