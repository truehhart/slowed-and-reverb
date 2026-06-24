import { invoke, isTauri, listen } from "./tauri";
import * as audio from "./audio";

export type Track = {
  id: string;
  title: string;
  webpage_url: string;
  thumbnail_url?: string | null;
};
type CachedAudio = { path: string; title: string | null };
export type RepeatMode = "off" | "queue" | "one";

export type Status =
  | "idle"
  | "resolving"
  | "downloading"
  | "decoding"
  | "playing"
  | "paused"
  | "failed";

let queue: Track[] = [];
let index = -1;
let playToken = 0; // bumped per playIndex; a stale download won't start audio
let consecutiveFailures = 0; // guards auto-skip from looping a dead queue
let status: Status = "idle";
let repeat: RepeatMode = "off";
const listeners: Array<() => void> = [];
let onProgress: ((percent: number | null) => void) | null = null;
const pathCache = new Map<string, string>();
const preloadPromises = new Map<string, Promise<string>>();
const PREV_RESTART_SECONDS = 2;
const LOOKAHEAD_COUNT = 2;

// yt-dlp download progress, emitted from Rust. Surfaced to the UI so a
// long album-length download shows movement instead of looking hung.
void listen<number>("download-progress", (e) => {
  console.debug("[player] download progress:", e.payload);
  onProgress?.(e.payload);
});

function requireTauri(): void {
  if (!isTauri()) {
    throw new Error(
      "open this with Tauri (`mise run dev` or the .app), not a browser tab",
    );
  }
}

export function onChange(cb: () => void): void {
  listeners.push(cb);
}
export function setOnProgress(cb: (percent: number | null) => void): void {
  onProgress = cb;
}
function emit(): void {
  for (const l of listeners) l();
}

export function getQueue(): Track[] {
  return queue;
}
export function getIndex(): number {
  return index;
}
export function current(): Track | null {
  return queue[index] ?? null;
}

/** Seconds to start at, from a YouTube `t`/`start` param (`90`, `1m30s`, …). */
export function parseStartSeconds(url: string): number {
  let params: URLSearchParams;
  try {
    params = new URL(url).searchParams;
  } catch {
    return 0;
  }
  const raw = params.get("t") ?? params.get("start");
  if (!raw) return 0;
  if (/^\d+$/.test(raw)) return Number(raw);
  const m = raw.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/i);
  if (!m || !m[0]) return 0;
  return (
    (Number(m[1]) || 0) * 3600 + (Number(m[2]) || 0) * 60 + (Number(m[3]) || 0)
  );
}

/** True for any http(s) URL. Used to gate paste-to-add so stray clipboard text
 * is silently ignored — the host isn't checked because yt-dlp resolves far more
 * than YouTube (SoundCloud, Bandcamp, Vimeo, …); let the resolver judge the site. */
export function looksLikeUrl(text: string): boolean {
  let u: URL;
  try {
    u = new URL(text.trim());
  } catch {
    return false;
  }
  return u.protocol === "http:" || u.protocol === "https:";
}

function parseVideoId(url: string): string | null {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (u.searchParams.has("list")) return null; // playlist URLs still need resolve
  const host = u.hostname.replace(/^www\./, "");
  const id =
    host === "youtu.be"
      ? u.pathname.split("/").filter(Boolean)[0]
      : host.endsWith("youtube.com") && u.pathname === "/watch"
        ? u.searchParams.get("v")
        : host.endsWith("youtube.com") &&
            /^\/(shorts|embed|live)\//.test(u.pathname)
          ? u.pathname.split("/").filter(Boolean)[1]
          : null;
  return id && /^[A-Za-z0-9_-]{11}$/.test(id) ? id : null;
}

export function getStatus(): Status {
  return status;
}
export function repeatMode(): RepeatMode {
  return repeat;
}
export function toggleRepeat(): RepeatMode {
  repeat = repeat === "off" ? "queue" : repeat === "queue" ? "one" : "off";
  emit();
  return repeat;
}
function setStatus(s: Status): void {
  status = s;
  emit();
}

// Active yt-dlp downloads (foreground play + background preload). Surfaced so
// the status bar reads "downloading" with a percent whenever any download runs,
// not just the brief pre-play fetch.
let activeDownloads = 0;

export function isDownloading(): boolean {
  return activeDownloads > 0;
}

function downloadTrack(track: Track, background: boolean): Promise<string> {
  const cacheKey = track.id;
  const inFlight = preloadPromises.get(cacheKey);
  if (inFlight) return inFlight;

  activeDownloads++;
  emit();
  const download = invoke<string>("download_audio", {
    videoUrl: track.webpage_url,
    videoId: track.id,
    emitProgress: true,
  })
    .then((path) => {
      pathCache.set(cacheKey, path);
      return path;
    })
    .finally(() => {
      activeDownloads--;
      preloadPromises.delete(cacheKey);
      if (activeDownloads === 0) onProgress?.(null);
      emit();
    });
  if (background) preloadPromises.set(cacheKey, download);
  return download;
}

/** Drop the in-memory path/decode caches after the on-disk cache is purged,
 * so queued tracks re-download on next play instead of pointing at deleted
 * files. The track playing now keeps its decoded buffer and isn't interrupted. */
export function forgetCaches(): void {
  pathCache.clear();
  audio.clearDecodeCache();
}

async function preloadLookahead(
  anchorIndex: number,
  token: number,
): Promise<void> {
  for (let offset = 1; offset <= LOOKAHEAD_COUNT; offset++) {
    if (token !== playToken) return;
    const track = queue[anchorIndex + offset];
    if (!track || pathCache.has(track.id)) continue;

    try {
      await downloadTrack(track, true);
    } catch (e) {
      // A foreground selection supersedes background preloads by design.
      if (token === playToken) console.debug("[player] lookahead skipped:", e);
      return;
    }
  }
}

async function refreshCachedTitle(url: string, id: string): Promise<void> {
  const tracks = await invoke<Track[]>("resolve_tracks", { url });
  const track = tracks.find((t) => t.id === id) ?? tracks[0];
  if (!track || queue[0]?.id !== id) return;
  queue[0] = { ...queue[0], title: track.title };
  emit();
}

export async function load(url: string): Promise<void> {
  requireTauri();
  const startAt = parseStartSeconds(url);
  const cachedId = parseVideoId(url);
  if (cachedId) {
    try {
      const cached = await invoke<CachedAudio | null>("cached_audio", {
        videoId: cachedId,
      });
      if (cached) {
        queue = [
          {
            id: cachedId,
            title: cached.title ?? "cached video",
            webpage_url: url,
            thumbnail_url: null,
          },
        ];
        index = -1;
        pathCache.set(cachedId, cached.path);
        emit();
        if (!cached.title)
          void refreshCachedTitle(url, cachedId).catch(console.debug);
        await playIndex(0, startAt);
        return;
      }
    } catch (e) {
      console.debug("[player] cache lookup failed:", e);
    }
  }
  setStatus("resolving");
  try {
    queue = await invoke<Track[]>("resolve_tracks", { url });
  } catch (e) {
    setStatus("failed");
    throw e;
  }
  index = -1;
  emit();
  // A timecode in the pasted URL applies to the first track only.
  if (queue.length) await playIndex(0, startAt);
}

/** Resolve `url` and append its track(s) to the queue, leaving playback alone.
 * Starts playing the first appended track only if nothing is playing yet.
 * Returns how many tracks were just added (0 if the URL resolved to nothing). */
export async function add(url: string): Promise<number> {
  requireTauri();
  const tracks = await invoke<Track[]>("resolve_tracks", { url });
  if (!tracks.length) return 0;
  const startFrom = queue.length;
  queue = [...queue, ...tracks];
  emit();
  // index < 0 means nothing has been selected — kick off the first new track.
  if (index < 0) await playIndex(startFrom);
  return tracks.length;
}

/** A track failed to download or decode (e.g. age-gated video yt-dlp can't
 * fetch without auth). Skip to the next one instead of stalling on "failed";
 * give up only once the whole queue has proved unplayable. */
async function skipFailedTrack(
  failedIndex: number,
  token: number,
): Promise<void> {
  if (token !== playToken) return;
  audio.stop();
  consecutiveFailures++;
  const nextIndex =
    failedIndex + 1 < queue.length
      ? failedIndex + 1
      : repeat === "queue"
        ? 0
        : -1;
  if (nextIndex < 0 || consecutiveFailures >= queue.length) {
    consecutiveFailures = 0;
    setStatus("failed");
    return;
  }
  await playIndex(nextIndex);
}

export async function playIndex(i: number, startAt = 0): Promise<void> {
  if (i < 0 || i >= queue.length) return;
  requireTauri();
  const token = ++playToken;
  // Stop the outgoing track now, before any download/decode: otherwise it keeps
  // playing under the new track's UI state, and its onended could even
  // auto-advance past the user's selection.
  audio.stop();
  const track = queue[i];
  const cacheKey = track.id;
  index = i;
  onProgress?.(null);
  let path = pathCache.get(cacheKey);
  if (path) {
    console.debug("[player] download cache hit:", path);
    // No download_audio runs on a cache hit, so supersede any in-flight one
    // (its generation would otherwise stay current and keep emitting progress).
    void invoke("cancel_download").catch(console.debug);
  } else {
    setStatus("downloading");
    console.debug("[player] download start:", track.webpage_url);
    try {
      path = await downloadTrack(track, false);
    } catch (e) {
      // A newer selection superseded this download and Rust killed it; that's
      // expected, not a user-facing error. Anything else means this track is
      // unplayable — skip to the next instead of stalling.
      if (token !== playToken) return;
      console.warn("[player] download failed, skipping:", track.title, e);
      return skipFailedTrack(i, token);
    }
    console.debug("[player] download ready:", path);
  }
  if (token !== playToken) return; // a newer selection superseded this one
  onProgress?.(null);
  setStatus("decoding");
  audio.setOnEnded(() => {
    console.debug("[player] auto-advance");
    void next(true);
  });
  try {
    await audio.playPath(path, startAt, () => token === playToken);
  } catch (e) {
    if (token !== playToken) return;
    console.warn("[player] decode failed, skipping:", track.title, e);
    return skipFailedTrack(i, token);
  }
  if (token !== playToken) return;
  consecutiveFailures = 0; // a track played; the queue isn't dead
  setStatus("playing");
  void preloadLookahead(i, token);
}

/** Play/pause toggle that keeps status in sync. Returns true if now paused. */
export async function togglePause(): Promise<boolean> {
  if (status === "idle" && current() && (await audio.restart())) {
    setStatus("playing");
    return false;
  }
  // Only a playing/paused track can be toggled — ignore when idle (nothing
  // loaded, or the queue ended) or mid-load, else we'd suspend an empty context
  // and report a bogus paused/playing state.
  if (status !== "playing" && status !== "paused") return false;
  const paused = await audio.togglePause();
  setStatus(paused ? "paused" : "playing");
  return paused;
}

export async function next(fromEnded = false): Promise<void> {
  if (fromEnded && repeat === "one" && index >= 0) await playIndex(index);
  else if (index + 1 < queue.length) await playIndex(index + 1);
  else if (repeat === "queue" && queue.length) await playIndex(0);
  else setStatus("idle"); // reached the end → nothing playing
}

export async function skipNext(): Promise<void> {
  if (!queue.length) return;
  await playIndex(index + 1 < queue.length ? index + 1 : 0);
}

export async function skipPrev(): Promise<void> {
  if (!queue.length) return;
  await playIndex(index - 1 >= 0 ? index - 1 : queue.length - 1);
}

export async function prev(): Promise<void> {
  const hasPrevious = index - 1 >= 0;
  const canRestart = status === "playing" || status === "paused";
  if (
    canRestart &&
    (!hasPrevious || audio.currentTime() > PREV_RESTART_SECONDS) &&
    (await audio.restart())
  ) {
    setStatus("playing");
    return;
  }
  if (hasPrevious) await playIndex(index - 1);
}

/** Empty the queue and stop playback. */
export function clear(): void {
  playToken++; // a stale in-flight download won't start audio
  audio.stop();
  queue = [];
  index = -1;
  consecutiveFailures = 0;
  onProgress?.(null);
  setStatus("idle"); // emits
}
