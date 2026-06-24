//! Thin wrappers over the bundled `yt-dlp` CLI. All YouTube/network/filesystem
//! I/O lives here so the webview needs no fs/http permissions.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    io::{BufRead, BufReader, Read},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    thread,
};
use tauri::{Emitter, Manager};

#[derive(Serialize)]
pub struct Track {
    id: String,
    title: String,
    webpage_url: String,
    thumbnail_url: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct CachedMeta {
    title: String,
}

#[derive(Serialize)]
pub struct CachedAudio {
    path: String,
    title: Option<String>,
}

/// Monotonic download generation. Each `download_audio` bumps it; an in-flight
/// download whose generation is no longer current kills its own yt-dlp child.
#[derive(Default)]
pub struct Downloads(pub Arc<AtomicU64>);

// Modest AAC-first default. WKWebView reliably decodes AAC/m4a, so prefer it
// and fall back through mp3 to any audio. A bare `bestaudio` often returns
// Opus-in-WebM, which fails with a "codec unavailable" error.
const AUDIO_FORMAT: &str =
    "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=mp3]/bestaudio";

fn cached_audio_path(cache_dir: &Path, video_id: &str) -> Result<Option<String>, String> {
    for entry in std::fs::read_dir(cache_dir).map_err(|e| e.to_string())? {
        let path = entry.map_err(|e| e.to_string())?.path();
        if path.is_file()
            && path.extension().and_then(|s| s.to_str()) != Some("json")
            && path.file_stem().and_then(|s| s.to_str()) == Some(video_id)
        {
            return Ok(Some(path.to_string_lossy().to_string()));
        }
    }
    Ok(None)
}

/// Absolute path of the cached cover art for a video (`<id>_thumb.<ext>`), if
/// `ensure_thumbnail` has fetched it. Used to feed the OS Now Playing artwork a
/// local file instead of refetching over the network on every update.
pub fn thumbnail_path(app: &tauri::AppHandle, video_id: &str) -> Option<PathBuf> {
    let cache_dir = app.path().app_cache_dir().ok()?;
    let stem = format!("{video_id}_thumb");
    std::fs::read_dir(&cache_dir).ok()?.flatten().find_map(|e| {
        let path = e.path();
        (path.is_file() && path.file_stem().and_then(|s| s.to_str()) == Some(stem.as_str()))
            .then_some(path)
    })
}

/// Ensure cover art for `video_id` is cached, downloading it from `url` if
/// missing. Independent of the audio download so art loads in parallel and
/// cached-audio tracks still get a cover. Returns the local path.
pub async fn ensure_thumbnail(
    app: tauri::AppHandle,
    video_id: String,
    url: String,
) -> Option<PathBuf> {
    if let Some(path) = thumbnail_path(&app, &video_id) {
        return Some(path);
    }
    let cache_dir = app.path().app_cache_dir().ok()?;
    std::fs::create_dir_all(&cache_dir).ok()?;
    let ext = if url
        .split('?')
        .next()
        .unwrap_or(&url)
        .to_ascii_lowercase()
        .ends_with(".webp")
    {
        "webp"
    } else {
        "jpg"
    };
    let path = cache_dir.join(format!("{video_id}_thumb.{ext}"));
    tauri::async_runtime::spawn_blocking(move || -> Result<PathBuf, String> {
        let resp = ureq::get(&url).call().map_err(|e| e.to_string())?;
        let mut bytes = Vec::new();
        resp.into_reader()
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        std::fs::write(&path, &bytes).map_err(|e| e.to_string())?;
        Ok(path)
    })
    .await
    .ok()?
    .ok()
}

fn meta_path(cache_dir: &Path, video_id: &str) -> PathBuf {
    cache_dir.join(format!("{video_id}.json"))
}

fn read_cached_title(cache_dir: &Path, video_id: &str) -> Option<String> {
    let bytes = std::fs::read(meta_path(cache_dir, video_id)).ok()?;
    let meta: CachedMeta = serde_json::from_slice(&bytes).ok()?;
    Some(meta.title)
}

fn write_cached_title(cache_dir: &Path, track: &Track) -> Result<(), String> {
    let meta = CachedMeta {
        title: track.title.clone(),
    };
    let bytes = serde_json::to_vec(&meta).map_err(|e| e.to_string())?;
    std::fs::write(meta_path(cache_dir, &track.id), bytes).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn cached_audio(
    app: tauri::AppHandle,
    video_id: String,
) -> Result<Option<CachedAudio>, String> {
    let cache_dir = app.path().app_cache_dir().map_err(|e| e.to_string())?;
    if !cache_dir.is_dir() {
        return Ok(None);
    }
    Ok(
        cached_audio_path(&cache_dir, &video_id)?.map(|path| CachedAudio {
            path,
            title: read_cached_title(&cache_dir, &video_id),
        }),
    )
}

/// Supersede any in-flight download by bumping the generation. Called when a
/// cached track is selected (no `download_audio` runs), so a stale yt-dlp child
/// stops emitting progress and exits instead of racing the new playback.
#[tauri::command]
pub fn cancel_download(state: tauri::State<'_, Downloads>) {
    state.0.fetch_add(1, Ordering::SeqCst);
}

/// Total bytes of cached files in the app cache dir (0 if it doesn't exist).
// ponytail: flat cache dir, no subdirs — top-level files only, no recursion.
#[tauri::command]
pub fn cache_size(app: tauri::AppHandle) -> Result<u64, String> {
    let cache_dir = app.path().app_cache_dir().map_err(|e| e.to_string())?;
    if !cache_dir.is_dir() {
        return Ok(0);
    }
    let mut total = 0;
    for entry in std::fs::read_dir(&cache_dir).map_err(|e| e.to_string())? {
        let meta = entry.map_err(|e| e.to_string())?.metadata();
        if let Ok(meta) = meta {
            if meta.is_file() {
                total += meta.len();
            }
        }
    }
    Ok(total)
}

/// Delete every cached file (audio, thumbnails, meta) from the app cache dir.
#[tauri::command]
pub fn purge_cache(app: tauri::AppHandle) -> Result<(), String> {
    let cache_dir = app.path().app_cache_dir().map_err(|e| e.to_string())?;
    // Destructive-op guard: app_cache_dir() is `<os cache>/<bundle id>` and is
    // never user-supplied, but refuse anyway unless the resolved path is our own
    // identifier-scoped dir — a misconfig must never aim this at a broad path.
    // Paired with remove_file-only (no recursion, no remove_dir_all) below, the
    // blast radius is "top-level files in our cache dir", never a tree.
    if !cache_dir.ends_with(&app.config().identifier) {
        return Err(format!("refusing to purge unexpected path: {cache_dir:?}"));
    }
    if !cache_dir.is_dir() {
        return Ok(());
    }
    for entry in std::fs::read_dir(&cache_dir).map_err(|e| e.to_string())? {
        let _ = std::fs::remove_file(entry.map_err(|e| e.to_string())?.path());
    }
    Ok(())
}

/// Pull the percentage out of a yt-dlp `[download]  12.3% of …` progress line.
fn parse_percent(line: &str) -> Option<f64> {
    let rest = &line[line.find("[download]")? + "[download]".len()..];
    let rest = rest.trim_start();
    rest[..rest.find('%')?].trim().parse().ok()
}

fn ytdlp(app: &tauri::AppHandle) -> PathBuf {
    if let Ok(path) = app.path().resource_dir().map(|dir| dir.join("yt-dlp")) {
        if path.is_file() {
            return path;
        }
    }

    "yt-dlp".into()
}

/// Prime yt-dlp's page cache at startup so the first real fetch doesn't eat the
/// ~0.3s PyInstaller cold start (reading the bundled `_internal` libs off disk).
/// Fire-and-forget; the network cost of a real fetch dwarfs this, so failure is
/// harmless.
pub fn warm_up(app: &tauri::AppHandle) {
    let bin = ytdlp(app);
    thread::spawn(move || {
        let _ = Command::new(bin)
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .output();
    });
}

/// Run a configured yt-dlp command off the async runtime. Returns stdout on success,
/// or the trimmed stderr (so failures surface to the UI).
async fn run_ytdlp(mut cmd: Command) -> Result<Vec<u8>, String> {
    let out = tauri::async_runtime::spawn_blocking(move || cmd.output())
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| format!("failed to launch bundled yt-dlp: {e}"))?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    Ok(out.stdout)
}

/// Flat-playlist entries for unavailable videos (private, deleted, age-gated)
/// carry a bracketed placeholder title — `[Private video]`, `[Deleted video]`,
/// `[Unavailable video]` — or none at all. They'd fail at download time, so we
/// drop them at resolve instead of queuing a track that can never play.
fn is_unavailable_title(title: &str) -> bool {
    let t = title.trim();
    t.starts_with('[')
        && t.ends_with(']')
        && ["private", "deleted", "unavailable"]
            .iter()
            .any(|kw| t.to_ascii_lowercase().contains(kw))
}

fn push_track(tracks: &mut Vec<Track>, entry: &Value) {
    let id = entry.get("id").and_then(Value::as_str).unwrap_or_default();
    if id.is_empty() {
        return;
    }
    let title = match entry.get("title").and_then(Value::as_str) {
        Some(t) if !t.is_empty() && !is_unavailable_title(t) => t.to_string(),
        // No title (or a placeholder one) means yt-dlp couldn't reach the video.
        _ => return,
    };
    // Flat-playlist entries may omit webpage_url; reconstruct it from the id.
    let webpage_url = entry
        .get("webpage_url")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| format!("https://www.youtube.com/watch?v={id}"));
    let thumbnail_url = entry
        .get("thumbnail")
        .and_then(Value::as_str)
        .map(str::to_string)
        .or_else(|| {
            entry
                .get("thumbnails")
                .and_then(Value::as_array)
                .and_then(|xs| xs.last())
                .and_then(|x| x.get("url"))
                .and_then(Value::as_str)
                .map(str::to_string)
        });
    tracks.push(Track {
        id: id.to_string(),
        title,
        webpage_url,
        thumbnail_url,
    });
}

/// Expand a video or playlist URL into a queue of tracks (metadata only — fast).
#[tauri::command]
pub async fn resolve_tracks(app: tauri::AppHandle, url: String) -> Result<Vec<Track>, String> {
    let mut cmd = Command::new(ytdlp(&app));
    cmd.args(["-J", "--flat-playlist", "--no-warnings"]);
    cmd.arg(&url);
    let stdout = run_ytdlp(cmd).await?;

    let json: Value = serde_json::from_slice(&stdout).map_err(|e| e.to_string())?;
    let mut tracks = Vec::new();
    match json.get("entries").and_then(Value::as_array) {
        Some(entries) => entries.iter().for_each(|e| push_track(&mut tracks, e)),
        None => push_track(&mut tracks, &json),
    }
    if tracks.is_empty() {
        return Err("no playable tracks found".into());
    }
    if let Ok(cache_dir) = app.path().app_cache_dir() {
        let _ = std::fs::create_dir_all(&cache_dir);
        for track in &tracks {
            let _ = write_cached_title(&cache_dir, track);
        }
    }
    Ok(tracks)
}

/// Download one track's audio to the app cache dir; return the absolute file
/// path. Emits `download-progress` (percent) events as it runs, and kills its
/// yt-dlp child if a newer `download_audio` call supersedes it (track switch).
#[tauri::command]
pub async fn download_audio(
    app: tauri::AppHandle,
    state: tauri::State<'_, Downloads>,
    video_url: String,
    video_id: String,
    emit_progress: Option<bool>,
) -> Result<String, String> {
    // Bump the generation first: this call is now the current selection, so any
    // older in-flight download is superseded — even on a cache hit, where we'd
    // otherwise leave a stale yt-dlp child emitting progress over the new track.
    let gen = state.0.clone();
    let my_gen = gen.fetch_add(1, Ordering::SeqCst) + 1;

    let cache_dir = app.path().app_cache_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&cache_dir).map_err(|e| e.to_string())?;
    if let Some(path) = cached_audio_path(&cache_dir, &video_id)? {
        return Ok(path);
    }
    let out_template = cache_dir
        .join("%(id)s.%(ext)s")
        .to_string_lossy()
        .to_string();

    let emit_progress = emit_progress.unwrap_or(true);

    tauri::async_runtime::spawn_blocking(move || {
        let mut cmd = Command::new(ytdlp(&app));
        // No `-x`/`--extract-audio` (that needs ffmpeg) — grab a pre-encoded
        // audio stream. `--print after_move:filepath --no-simulate` downloads
        // and prints the final on-disk path; plain `filepath` evaluates before
        // the file is in place and prints "NA" on a fresh download. after_move
        // reports the path for already-cached files too.
        // `--newline --progress` makes progress one parseable line per update.
        cmd.args([
            "-f",
            AUDIO_FORMAT,
            "--no-playlist",
            "--no-warnings",
            "--newline",
            "--progress",
            "-o",
            &out_template,
            "--print",
            "after_move:filepath",
            "--no-simulate",
        ]);
        cmd.arg(&video_url);
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        let mut child = cmd
            .spawn()
            .map_err(|e| format!("failed to launch bundled yt-dlp: {e}"))?;
        let stdout = child.stdout.take().expect("stdout piped");
        let stderr = child.stderr.take().expect("stderr piped");
        let child = Arc::new(Mutex::new(child));

        // Drain stderr on its own thread (avoids a full-pipe deadlock while we
        // block reading stdout): emit progress, collect real errors, and kill
        // the child if a newer download has superseded us.
        let killer = child.clone();
        let gen_e = gen.clone();
        let app_e = app.clone();
        let stderr_thread = thread::spawn(move || {
            let mut errs: Vec<String> = Vec::new();
            for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                // Stop before emitting once superseded, so a stale progress
                // event can't overwrite the new track's state.
                if gen_e.load(Ordering::SeqCst) != my_gen {
                    let _ = killer.lock().unwrap().kill();
                    break;
                }
                if let Some(p) = parse_percent(&line) {
                    if emit_progress {
                        let _ = app_e.emit("download-progress", p);
                    }
                } else if !line.trim().is_empty() {
                    errs.push(line);
                }
            }
            errs.join("\n")
        });

        // yt-dlp prints the filepath to stdout after the download completes;
        // progress may land here instead of stderr depending on the build, so
        // parse it from both. The path is the last non-`[download]` line.
        let mut path = String::new();
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if gen.load(Ordering::SeqCst) != my_gen {
                let _ = child.lock().unwrap().kill();
                break;
            }
            if let Some(p) = parse_percent(&line) {
                if emit_progress {
                    let _ = app.emit("download-progress", p);
                }
            }
            let t = line.trim();
            if !t.is_empty() && !t.starts_with('[') {
                path = t.to_string();
            }
        }

        let errs = stderr_thread.join().unwrap_or_default();
        let status = child.lock().unwrap().wait().map_err(|e| e.to_string())?;

        if gen.load(Ordering::SeqCst) != my_gen {
            return Err("download superseded".to_string());
        }
        if !status.success() {
            return Err(if errs.is_empty() {
                "yt-dlp failed".to_string()
            } else {
                errs
            });
        }
        if path.is_empty() {
            return Err("yt-dlp did not report an output path".into());
        }
        Ok(path)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_cache_dir(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock before unix epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "slowed-and-reverb-ytdlp-{name}-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp cache dir");
        dir
    }

    #[test]
    fn parse_percent_reads_ytdlp_progress_lines() {
        assert_eq!(
            parse_percent("[download]  12.3% of 4.00MiB at 1.00MiB/s"),
            Some(12.3)
        );
        assert_eq!(parse_percent("[download] 100% of 4.00MiB"), Some(100.0));
        assert_eq!(parse_percent("ERROR: video unavailable"), None);
    }

    #[test]
    fn push_track_uses_defaults_for_sparse_flat_playlist_entries() {
        let mut tracks = Vec::new();

        push_track(
            &mut tracks,
            &json!({
                "id": "aaaaaaaaaaa",
                "title": "Sparse",
                "thumbnails": [
                    { "url": "https://img.example/small.jpg" },
                    { "url": "https://img.example/large.jpg" }
                ]
            }),
        );

        assert_eq!(tracks.len(), 1);
        assert_eq!(tracks[0].id, "aaaaaaaaaaa");
        assert_eq!(tracks[0].title, "Sparse");
        assert_eq!(
            tracks[0].webpage_url,
            "https://www.youtube.com/watch?v=aaaaaaaaaaa"
        );
        assert_eq!(
            tracks[0].thumbnail_url.as_deref(),
            Some("https://img.example/large.jpg")
        );
    }

    #[test]
    fn push_track_skips_unplayable_entries() {
        let mut tracks = Vec::new();

        // No id, no title, and bracketed placeholders are all unplayable.
        push_track(&mut tracks, &json!({ "title": "No id" }));
        push_track(
            &mut tracks,
            &json!({ "id": "bbbbbbbbbbb", "webpage_url": "https://example.test/watch" }),
        );
        push_track(
            &mut tracks,
            &json!({ "id": "ddddddddddd", "title": "[Private video]" }),
        );
        push_track(
            &mut tracks,
            &json!({ "id": "eeeeeeeeeee", "title": "[Deleted video]" }),
        );

        assert!(tracks.is_empty());

        // A real title survives.
        push_track(
            &mut tracks,
            &json!({ "id": "fffffffffff", "title": "Real Song" }),
        );
        assert_eq!(tracks.len(), 1);
        assert_eq!(tracks[0].title, "Real Song");
    }

    #[test]
    fn cache_helpers_find_audio_and_round_trip_title_metadata() {
        let dir = temp_cache_dir("cache");
        let track = Track {
            id: "ccccccccccc".into(),
            title: "Cached Title".into(),
            webpage_url: "https://www.youtube.com/watch?v=ccccccccccc".into(),
            thumbnail_url: None,
        };
        let audio_path = dir.join("ccccccccccc.m4a");

        std::fs::write(&audio_path, b"audio").expect("write cached audio");
        std::fs::write(dir.join("ccccccccccc.json"), b"not the audio").expect("write decoy json");
        write_cached_title(&dir, &track).expect("write cached title");

        assert_eq!(
            cached_audio_path(&dir, "ccccccccccc").expect("scan cache"),
            Some(audio_path.to_string_lossy().to_string())
        );
        assert_eq!(
            read_cached_title(&dir, "ccccccccccc").as_deref(),
            Some("Cached Title")
        );

        std::fs::remove_dir_all(dir).expect("remove temp cache dir");
    }
}
