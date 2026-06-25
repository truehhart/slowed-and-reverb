mod ytdlp;

use souvlaki::{MediaControls, MediaMetadata, MediaPlayback, MediaPosition, PlatformConfig};
use std::collections::HashSet;
use std::path::Path;
use std::sync::{Mutex, MutexGuard, Once};
use std::time::Duration;
use tauri::{Emitter, Manager};

// In-flight cover-art fetches, so rapid now-playing updates for the same track
// don't spawn duplicate downloads.
type InFlight = Mutex<HashSet<String>>;

static PANIC_HOOK: Once = Once::new();

fn install_panic_hook() {
    PANIC_HOOK.call_once(|| {
        let default_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            log::error!("slowed-and-reverb panic: {info}");
            eprintln!("slowed-and-reverb panic: {info}");
            default_hook(info);
        }));
    });
}

fn lock_or_recover<'a, T>(mutex: &'a Mutex<T>, name: &str) -> MutexGuard<'a, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            log::error!("recovering poisoned {name} mutex");
            eprintln!("recovering poisoned {name} mutex");
            poisoned.into_inner()
        }
    }
}

// Percent-encode a filesystem path into a file:// URL. souvlaki feeds the cover
// URL to NSURL(string:) on macOS, which returns nil — silently, no artwork — for
// any unescaped space or non-ASCII byte. Keep unreserved chars and the path
// separator; escape everything else per UTF-8 byte.
fn file_url(path: &Path) -> String {
    let mut url = String::from("file://");
    for &b in path.to_string_lossy().as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => {
                url.push(b as char)
            }
            _ => url.push_str(&format!("%{b:02X}")),
        }
    }
    url
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_url_escapes_spaces_and_unicode() {
        assert_eq!(
            file_url(Path::new("/Users/a b/Café/x_thumb.jpg")),
            "file:///Users/a%20b/Caf%C3%A9/x_thumb.jpg"
        );
    }
}

fn progress(position_sec: f64) -> Option<MediaPosition> {
    Some(MediaPosition(Duration::from_secs_f64(
        position_sec.max(0.0),
    )))
}

// Push the full now-playing entry (title, duration, cover, position) to the OS.
// Times are *perceived* seconds (real / playbackRate) so the Control Center
// scrubber tracks wall-clock despite the slow-down — souvlaki can't set the
// MPNowPlayingInfo playback rate, so we normalise to a 1× timeline instead.
fn apply(
    controls: &Mutex<MediaControls>,
    title: &str,
    duration_sec: f64,
    cover: Option<&str>,
    position_sec: f64,
    playing: bool,
) {
    let mut controls = lock_or_recover(controls, "media controls");
    let _ = controls.set_metadata(MediaMetadata {
        title: Some(title),
        cover_url: cover,
        duration: (duration_sec > 0.0).then(|| Duration::from_secs_f64(duration_sec)),
        ..Default::default()
    });
    let progress = progress(position_sec);
    let _ = controls.set_playback(if playing {
        MediaPlayback::Playing { progress }
    } else {
        MediaPlayback::Paused { progress }
    });
}

// One persistent MediaControls for the whole app lifetime. This is load-bearing:
// `MediaControls` runs `detach()` on Drop (souvlaki/src/lib.rs), which on macOS
// disables every command and removes the handlers — so a dropped/throwaway
// instance silently unregisters us and the OS hands media keys back to Music.
// Mirror the now-playing track + play state into the OS (Control Center / lock
// screen) so this app becomes the active Now Playing source and the keys route
// here.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
fn set_now_playing(
    app: tauri::AppHandle,
    controls: tauri::State<'_, Mutex<MediaControls>>,
    title: Option<String>,
    video_id: Option<String>,
    thumbnail_url: Option<String>,
    duration_sec: f64,
    position_sec: f64,
    playing: bool,
) {
    // No current track: hand the Now Playing session back cleanly.
    let Some(title) = title else {
        let _ = lock_or_recover(controls.inner(), "media controls")
            .set_playback(MediaPlayback::Stopped);
        return;
    };
    let cover = video_id
        .as_deref()
        .and_then(|id| ytdlp::thumbnail_path(&app, id))
        .map(|p| file_url(&p));
    apply(
        &controls,
        &title,
        duration_sec,
        cover.as_deref(),
        position_sec,
        playing,
    );

    // Cover not cached yet: fetch it asynchronously, then re-apply so Control
    // Center updates the moment the art lands.
    if cover.is_none() {
        if let (Some(id), Some(url)) = (video_id, thumbnail_url) {
            if !lock_or_recover(app.state::<InFlight>().inner(), "thumbnail fetches")
                .insert(id.clone())
            {
                return;
            }
            tauri::async_runtime::spawn(async move {
                let path = ytdlp::ensure_thumbnail(app.clone(), id.clone(), url).await;
                lock_or_recover(app.state::<InFlight>().inner(), "thumbnail fetches").remove(&id);
                if let Some(path) = path {
                    apply(
                        app.state::<Mutex<MediaControls>>().inner(),
                        &title,
                        duration_sec,
                        Some(&file_url(&path)),
                        position_sec,
                        playing,
                    );
                }
            });
        }
    }
}

// Lightweight position/state tick: updates the scrubber without rebuilding the
// metadata dict (which would re-load the artwork). Times are perceived seconds.
#[tauri::command]
fn update_position(
    controls: tauri::State<'_, Mutex<MediaControls>>,
    position_sec: f64,
    playing: bool,
) {
    let mut controls = lock_or_recover(controls.inner(), "media controls");
    let progress = progress(position_sec);
    let _ = controls.set_playback(if playing {
        MediaPlayback::Playing { progress }
    } else {
        MediaPlayback::Paused { progress }
    });
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    install_panic_hook();

    tauri::Builder::default()
        .plugin(tauri_plugin_updater::Builder::new().build())
        // Opens external links (the GitHub link in the header) in the system
        // browser; the webview itself still gets no fs/http reach.
        .plugin(tauri_plugin_opener::init())
        // Logs to the terminal and a rotating file in the app log dir. The
        // frontend mirrors its console here via @tauri-apps/plugin-log, so the
        // [player]/[audio] logs show up outside devtools too.
        .plugin(
            tauri_plugin_log::Builder::new()
                .targets([
                    tauri_plugin_log::Target::new(tauri_plugin_log::TargetKind::Stdout),
                    tauri_plugin_log::Target::new(tauri_plugin_log::TargetKind::LogDir {
                        file_name: None,
                    }),
                ])
                .build(),
        )
        .setup(|app| {
            use souvlaki::MediaControlEvent;

            let mut controls = MediaControls::new(PlatformConfig {
                dbus_name: "slowed-and-reverb",
                display_name: "Slowed & Reverb",
                hwnd: None,
            })?;

            // Route OS media commands (hardware keys, Control Center, headphones)
            // to the same "media-key" event the frontend already handles.
            let handle = app.handle().clone();
            controls.attach(move |event| {
                let action = match event {
                    MediaControlEvent::Play => "play",
                    MediaControlEvent::Pause => "pause",
                    MediaControlEvent::Toggle => "playpause",
                    MediaControlEvent::Next => "next",
                    MediaControlEvent::Previous => "prev",
                    _ => return,
                };
                let _ = handle.emit("media-key", action);
            })?;
            // Establish playback state at registration time, then keep the
            // instance alive (its Drop would detach everything — see the command).
            let _ = controls.set_playback(MediaPlayback::Stopped);
            app.manage(Mutex::new(controls));
            app.manage(InFlight::default());

            // Warm yt-dlp's page cache now so the first fetch skips the cold start.
            ytdlp::warm_up(app.handle());

            Ok(())
        })
        .manage(ytdlp::Downloads::default())
        .invoke_handler(tauri::generate_handler![
            ytdlp::resolve_tracks,
            ytdlp::cached_audio,
            ytdlp::download_audio,
            ytdlp::cancel_download,
            ytdlp::cache_size,
            ytdlp::purge_cache,
            set_now_playing,
            update_position
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
