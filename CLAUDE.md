# CLAUDE.md — slowed-and-reverb

`slowed-and-reverb` is a small **Tauri 2** desktop app (macOS-first) that plays YouTube audio **slowed and reverbed**. Paste a video or playlist URL; the Rust side resolves and downloads the audio with **yt-dlp**, and the frontend plays it through the **Web Audio API** — `playbackRate` for the slow (which also drops pitch, exactly the slowed aesthetic) and a `ConvolverNode` for reverb.

We deliberately **do not embed the YouTube player**: a cross-origin iframe's audio can't be tapped by the Web Audio API, and OS loopback capture is a platform nightmare. yt-dlp + local Web-Audio playback is the whole point.

## Hard rules

- **Rust owns all I/O.** yt-dlp invocation, the network, and temp files live in `src-tauri/src/ytdlp.rs`. The webview gets **no** fs/http permissions — keep the capability surface in `capabilities/default.json` minimal (`core:default`).
- **No `-x`/`--extract-audio`** in yt-dlp calls — it pulls in ffmpeg. Download a pre-encoded audio stream (`bestaudio[ext=m4a]/bestaudio`) instead.
- **Commands stay thin.** A `#[tauri::command]` parses args and delegates; always surface yt-dlp **stderr** in the `Err` string so failures are debuggable.
- **mise tasks are the only entry points** — never call raw `cargo` / `pnpm tauri`. Standalone scripts go in `mise-tasks/` and are **Nushell** (`#!/usr/bin/env nu`).
- **Conventional Commits**; **never commit without operator review**.
- yt-dlp is copied from PATH into a Tauri sidecar before dev/build. Packaged apps must use the bundled binary; PATH is only a build-time/dev fallback.
- **Check libraries before inventing audio or complex UI systems.** For Web Audio effects/analysis/scheduling, streaming/playback architecture, custom knobs, gestures, complex sliders, visualization, or layout-heavy interaction, first look for a small, well-maintained library that fits Tauri/WKWebView and the app's vanilla TS setup. Prefer a library when it handles hard domain behavior better than local code; implement locally only when the feature is tiny, stable, and cheaper than carrying the dependency.

## Commands (via mise — always use these)

| Command          | What                                                                                     |
| ---------------- | ---------------------------------------------------------------------------------------- |
| `mise install`   | install toolchain (rust stable, node, pnpm, yt-dlp)                                      |
| `pnpm install`   | install JS deps (run once after `mise install`)                                          |
| `mise run dev`   | run the app with hot reload (`tauri dev`)                                                |
| `mise run build` | build the `.app` bundle                                                                  |
| `mise run check` | DOM-id guard + type-check (`tsc --noEmit`) + `cargo fmt --check` + clippy (= pre-commit) |
| `mise run test`  | Vitest (`src/ui-math.ts`, `src/player.ts`) + Rust unit tests + Playwright design tests   |
| `mise run fmt`   | prettier + `cargo fmt`                                                                   |
| `mise run lint`  | clippy                                                                                   |

## Layout

| Path                            | Purpose                                                   |
| ------------------------------- | --------------------------------------------------------- |
| `index.html`, `src/`            | vanilla TS + Vite frontend                                |
| `src/audio.ts`                  | Web Audio graph (speed + reverb) + impulse-response synth |
| `src/player.ts`                 | queue / now-playing state, `invoke()` calls, auto-advance |
| `src-tauri/src/ytdlp.rs`        | `resolve_tracks` + `download_audio` commands              |
| `src-tauri/src/lib.rs`          | Tauri builder: plugins + command registration             |
| `src-tauri/tauri.conf.json`     | window, asset-protocol scope, CSP, bundle                 |
| `src-tauri/capabilities/*.json` | permission grants for the main window                     |

## Distribution

`src-tauri/Cargo.toml` is the single checked-in release version. Releases are cut by dispatching the **`release`** workflow; it reads the Cargo package version, fails if the `v<version>` tag or GitHub release already exists, runs `check`, and pushes the tag. That tag triggers **`publish`**, which builds via `tauri-apps/tauri-action` with `src-tauri/tauri.updater.conf.json` and attaches the `.app`, `.dmg`, signed updater archive/signature, and `latest.json` to a published GitHub release, then pushes a Homebrew cask to `truehhart/homebrew-tap` (install via `brew install --cask truehhart/tap/slowed-and-reverb`). Builds are **arm64-only** (yt-dlp ships as an arch-specific resource) and **unsigned** (no Apple Developer cert yet) — the cask strips quarantine in `postflight`; a manual `.dmg`/`.app` install needs `xattr -dr com.apple.quarantine <app>` or right-click → Open. Tauri updater signing uses `TAURI_SIGNING_PRIVATE_KEY`; do not rotate or lose it unless intentionally breaking updates for already-installed apps. Apple signing/notarization (`APPLE_*` secrets feeding tauri-action) is a documented later add. The cross-repo tag and cask pushes use a GitHub App token (`RELEASE_APP_ID` / `RELEASE_APP_PRIVATE_KEY` secrets). See `.github/CLAUDE.md` for the GitHub Actions conventions.
