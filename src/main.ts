import "./log"; // install console→logfile mirror before anything logs
import { getVersion } from "@tauri-apps/api/app";
import { check } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";
import { invoke, listen, appWindow, isTauri } from "./tauri";
import * as audio from "./audio";
import * as player from "./player";
import { clamp, fmt, fmtCounter, angleFromValue, pctToUnit } from "./ui-math";

function el<T extends HTMLElement>(id: string): T {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing #${id}`);
  return node as T;
}

const urlInput = el<HTMLInputElement>("url");
const importBtn = el<HTMLButtonElement>("import");
const clearBtn = el<HTMLButtonElement>("clear");
const addRow = el<HTMLDivElement>("addRow");
const playPauseBtn = el<HTMLButtonElement>("playpause");
const prevBtn = el<HTMLButtonElement>("prev");
const nextBtn = el<HTMLButtonElement>("next");
const backBtn = el<HTMLButtonElement>("back");
const fwdBtn = el<HTMLButtonElement>("fwd");
const repeatBtn = el<HTMLButtonElement>("repeat");
const scrubber = el<HTMLInputElement>("scrubber");
const elapsedEl = el<HTMLSpanElement>("elapsed");
const remainingEl = el<HTMLSpanElement>("remaining");
const muteBtn = el<HTMLButtonElement>("mute");
const volumeInput = el<HTMLInputElement>("volume");
const reverbTypeGroup = el<HTMLDivElement>("reverbType");
const reverbCutoffGroup = el<HTMLDivElement>("reverbCutoff");
const speedKnob = el<HTMLDivElement>("speedKnob");
const speedInput = el<HTMLInputElement>("speed");
const reverbKnob = el<HTMLDivElement>("reverbKnob");
const reverbInput = el<HTMLInputElement>("reverb");
const queueEl = el<HTMLUListElement>("queue");
const ghLink = el<HTMLAnchorElement>("gh");
const nowEl = el<HTMLElement>("now");
const stateEl = el<HTMLSpanElement>("state");
const downloadingEl = el<HTMLSpanElement>("downloading");
const statusEl = el<HTMLSpanElement>("status");
const winCloseBtn = el<HTMLButtonElement>("win-close");
const winMinBtn = el<HTMLButtonElement>("win-min");
const winZoomBtn = el<HTMLButtonElement>("win-zoom");
const versionEl = document.querySelector<HTMLSpanElement>(".plate__model");

// Queried (not id-guarded): pure feedback decoration.
const vuTracks = Array.from(
  document.querySelectorAll<HTMLDivElement>("[data-vu]"),
);
const counterEl = document.querySelector<HTMLDivElement>("[data-counter]");
const nowTitle = document.querySelector<HTMLElement>(".nowtitle");

const SEEK_STEP = 5; // seconds for skip buttons / arrow keys
const VOL_STEP = 0.05;
const KNOB_DRAG_PX_PER_RANGE = 240;

function setStatus(msg: string, isError = false): void {
  statusEl.textContent = msg;
  stateEl.classList.toggle("error", isError);
}
const showError = (e: unknown): void => setStatus(String(e), true);

// Transient status message (e.g. "queued 12 tracks") that clears itself after a
// few seconds, unless a newer message has since replaced it.
let statusFlashTimer: ReturnType<typeof setTimeout> | undefined;
function flashStatus(msg: string): void {
  setStatus(msg);
  clearTimeout(statusFlashTimer);
  statusFlashTimer = setTimeout(() => {
    if (statusEl.textContent === msg) setStatus("");
  }, 4000);
}

async function showAppVersion(): Promise<void> {
  if (!versionEl || !isTauri()) return;

  try {
    versionEl.textContent = `v${await getVersion()}`;
  } catch (e) {
    console.debug("app version lookup failed", e);
  }
}

void showAppVersion();

async function checkForAppUpdate(): Promise<void> {
  if (!isTauri()) return;

  try {
    const update = await check();
    if (!update) return;

    const shouldInstall = window.confirm(
      `Install Slowed and Reverb ${update.version} now?`,
    );
    if (!shouldInstall) {
      flashStatus(`update ${update.version} available`);
      return;
    }

    let downloaded = 0;
    let contentLength: number | undefined;
    setStatus(`updating to ${update.version}`);
    await update.downloadAndInstall((event) => {
      switch (event.event) {
        case "Started":
          contentLength = event.data.contentLength;
          downloaded = 0;
          break;
        case "Progress":
          downloaded += event.data.chunkLength;
          if (contentLength) {
            setStatus(
              `updating ${Math.round((downloaded / contentLength) * 100)}%`,
            );
          }
          break;
        case "Finished":
          setStatus("update installed");
          break;
      }
    });
    await relaunch();
  } catch (e) {
    console.debug("update check failed", e);
  }
}

void checkForAppUpdate();

// Download indicator, independent of the player status: shows "downloading"
// (with a live percent once yt-dlp reports one) whenever any track — the one
// about to play or a background preload — is being fetched.
let downloadPercent: number | null = null;
function updateDownloadIndicator(): void {
  if (!player.isDownloading()) {
    downloadingEl.textContent = "";
    return;
  }
  downloadingEl.textContent =
    downloadPercent === null
      ? "downloading"
      : `downloading ${Math.round(downloadPercent)}%`;
}

let seeking = false; // true while the user drags the scrubber

function updateSeekUI(): void {
  const dur = audio.duration();
  scrubber.max = String(dur);
  const cur = seeking ? Number(scrubber.value) : audio.currentTime();
  const speed = audio.speed();
  if (!seeking) scrubber.value = String(cur);
  const perceived = cur / speed;
  elapsedEl.textContent = fmt(perceived);
  remainingEl.textContent = `-${fmt((dur - cur) / speed)}`;
  if (counterEl) counterEl.textContent = fmtCounter(perceived);
  scrubber.style.setProperty("--fill", `${dur > 0 ? (cur / dur) * 100 : 0}%`);
}

function updateMuteIcon(): void {
  muteBtn.classList.toggle("is-muted", audio.isMuted());
}

function runMediaAction(
  action: "play" | "pause" | "playpause" | "prev" | "next" | "back" | "fwd",
): void {
  switch (action) {
    case "play":
      if (player.getStatus() !== "playing")
        void player.togglePause().catch(showError);
      break;
    case "pause":
      if (player.getStatus() === "playing")
        void player.togglePause().catch(showError);
      break;
    case "playpause":
      void player.togglePause().catch(showError);
      break;
    case "prev":
      void player.skipPrev().catch(showError);
      break;
    case "next":
      void player.skipNext().catch(showError);
      break;
    case "back":
      seekBy(-SEEK_STEP);
      break;
    case "fwd":
      seekBy(SEEK_STEP);
      break;
  }
}

void listen<"play" | "pause" | "playpause" | "prev" | "next" | "back" | "fwd">(
  "media-key",
  (event) => runMediaAction(event.payload),
).catch(console.debug);

function updateMediaSession(): void {
  const cur = player.current();
  // Push now-playing into the OS (lock screen / Control Center) and keep this
  // app the active Now Playing source so hardware media keys route here. Times
  // are perceived seconds (real / speed) so the scrubber tracks wall-clock.
  const speed = audio.speed() || 1;
  void invoke("set_now_playing", {
    title: cur?.title ?? null,
    videoId: cur?.id ?? null,
    thumbnailUrl: cur?.thumbnail_url ?? null,
    durationSec: cur ? audio.duration() / speed : 0,
    positionSec: cur ? audio.currentTime() / speed : 0,
    playing: audio.isPlaying(),
  });
  if (!("mediaSession" in navigator)) return;
  // No artwork here: the remote thumbnail URL is blocked by img-src in the CSP,
  // and the OS Now Playing cover is supplied locally via the souvlaki path.
  navigator.mediaSession.metadata = cur
    ? new MediaMetadata({ title: cur.title })
    : null;
  const status = player.getStatus();
  navigator.mediaSession.playbackState = audio.isPlaying()
    ? "playing"
    : status === "paused"
      ? "paused"
      : "none";
}

if ("mediaSession" in navigator) {
  navigator.mediaSession.setActionHandler("play", () => runMediaAction("play"));
  navigator.mediaSession.setActionHandler("pause", () =>
    runMediaAction("pause"),
  );
  navigator.mediaSession.setActionHandler("previoustrack", () =>
    runMediaAction("prev"),
  );
  navigator.mediaSession.setActionHandler("nexttrack", () =>
    runMediaAction("next"),
  );
  navigator.mediaSession.setActionHandler("seekbackward", () =>
    runMediaAction("back"),
  );
  navigator.mediaSession.setActionHandler("seekforward", () =>
    runMediaAction("fwd"),
  );
}

// ---- knobs ---------------------------------------------------------------
function setKnob(
  knob: HTMLElement,
  input: HTMLInputElement,
  value: number,
  min: number,
  max: number,
): number {
  const v = Math.round(clamp(value, min, max));
  knob.style.setProperty("--knob-angle", `${angleFromValue(v, min, max)}deg`);
  knob.setAttribute("aria-valuenow", String(v));
  input.value = String(v);
  return v;
}

function applyControls(): void {
  const speedValue = setKnob(
    speedKnob,
    speedInput,
    Number(speedInput.value),
    50,
    100,
  );
  const reverbValue = setKnob(
    reverbKnob,
    reverbInput,
    Number(reverbInput.value),
    0,
    100,
  );
  audio.setSpeed(pctToUnit(speedValue));
  audio.setReverb(pctToUnit(reverbValue));
}

function bindKnob(
  knob: HTMLElement,
  input: HTMLInputElement,
  min: number,
  max: number,
  apply: () => void,
): void {
  let lastX = 0;
  let lastY = 0;
  let dragValue = 0;

  const setValue = (value: number): void => {
    input.value = String(Math.round(clamp(value, min, max)));
    apply();
  };

  const dragDelta = (e: PointerEvent): number => {
    const box = knob.getBoundingClientRect();
    const side = e.clientX >= box.left + box.width / 2 ? 1 : -1;
    return e.clientX - lastX + (e.clientY - lastY) * side;
  };

  input.addEventListener("focus", () => input.select());
  input.addEventListener("input", () => {
    const value = Number(input.value);
    if (Number.isFinite(value) && value >= min && value <= max) apply();
  });
  input.addEventListener("change", () => setValue(Number(input.value)));

  knob.addEventListener("pointerdown", (e) => {
    if (e.target === input) return;
    knob.setPointerCapture(e.pointerId);
    lastX = e.clientX;
    lastY = e.clientY;
    dragValue = Number(input.value);
  });

  knob.addEventListener("pointermove", (e) => {
    if (!knob.hasPointerCapture(e.pointerId)) return;
    const scale = (max - min) / KNOB_DRAG_PX_PER_RANGE;
    dragValue = clamp(dragValue + dragDelta(e) * scale, min, max);
    setValue(dragValue);
    lastX = e.clientX;
    lastY = e.clientY;
  });

  knob.addEventListener("keydown", (e) => {
    const steps: Record<string, number> = {
      ArrowUp: 1,
      ArrowRight: 1,
      ArrowDown: -1,
      ArrowLeft: -1,
      PageUp: 10,
      PageDown: -10,
      Home: min - Number(input.value),
      End: max - Number(input.value),
    };
    const delta = steps[e.key];
    if (delta === undefined) return;
    e.preventDefault();
    setValue(Number(input.value) + delta);
  });

  knob.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      setValue(Number(input.value) + (e.deltaY < 0 ? 1 : -1));
    },
    { passive: false },
  );
}

// ---- segmented tone controls (rewired away from <select>) ---------------
function selectedValue(group: HTMLElement): string {
  return (
    group.querySelector<HTMLButtonElement>('button[aria-selected="true"]')
      ?.dataset.value ?? ""
  );
}

function bindSegment(group: HTMLElement, apply: (value: string) => void): void {
  const buttons = Array.from(
    group.querySelectorAll<HTMLButtonElement>("button"),
  );
  const select = (btn: HTMLButtonElement): void => {
    for (const b of buttons) {
      const on = b === btn;
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
    }
    if (btn.dataset.value !== undefined) apply(btn.dataset.value);
  };
  // roving tabindex seed
  for (const b of buttons)
    b.tabIndex = b.getAttribute("aria-selected") === "true" ? 0 : -1;

  group.addEventListener("click", (e) => {
    const btn = (e.target as HTMLElement).closest("button");
    if (btn instanceof HTMLButtonElement && buttons.includes(btn)) select(btn);
  });
  group.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
    e.preventDefault();
    const i = buttons.findIndex(
      (b) => b.getAttribute("aria-selected") === "true",
    );
    const n =
      (i + (e.key === "ArrowRight" ? 1 : -1) + buttons.length) % buttons.length;
    select(buttons[n]);
    buttons[n].focus();
  });
}

// ---- playback feedback (VU + reels), only while playing ------------------
let rafId = 0;

function paintTrack(track: HTMLDivElement, level: number): void {
  const bars = track.children;
  const n = Math.round(level * bars.length);
  for (let i = 0; i < bars.length; i++) {
    bars[i].className = i < n ? (i >= bars.length - 2 ? "hot" : "on") : "";
  }
}

function paintFeedback(): void {
  const { l, r } = audio.getLevels();
  if (vuTracks[0]) paintTrack(vuTracks[0], l);
  if (vuTracks[1]) paintTrack(vuTracks[1], r);
  rafId = requestAnimationFrame(paintFeedback);
}

function startFeedback(): void {
  if (!rafId) rafId = requestAnimationFrame(paintFeedback);
}

function stopFeedback(): void {
  if (rafId) cancelAnimationFrame(rafId);
  rafId = 0;
  for (const track of vuTracks)
    for (const bar of track.children) bar.className = "";
}

// Download progress from yt-dlp; null clears the percent (all downloads done).
player.setOnProgress((percent) => {
  downloadPercent = percent;
  updateDownloadIndicator();
});

// Open the GitHub link in the system browser instead of navigating the webview.
ghLink.addEventListener("click", (e) => {
  e.preventDefault();
  void invoke("plugin:opener|open_url", { url: ghLink.href }).catch(showError);
});

// Marquee the now-playing title only when it overflows its fixed-width clip:
// measure the overflow, drive the keyframe shift, and scale the duration to the
// distance (~45px/s) so long and short titles both read at a steady pace.
function updateNowMarquee(): void {
  if (!nowTitle) return;
  nowEl.title = nowEl.textContent ?? "";
  nowTitle.classList.remove("is-scrolling");
  nowTitle.style.removeProperty("--marquee-shift");
  nowTitle.style.removeProperty("--marquee-dur");
  const overflow = nowEl.scrollWidth - nowEl.clientWidth;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (overflow > 4 && !reduce) {
    nowTitle.style.setProperty("--marquee-shift", `${-overflow}px`);
    nowTitle.style.setProperty(
      "--marquee-dur",
      `${Math.max(6, overflow / 45 + 4)}s`,
    );
    nowTitle.classList.add("is-scrolling");
  }
}

function render(): void {
  const tracks = player.getQueue();
  const idx = player.getIndex();
  queueEl.replaceChildren(
    ...tracks.map((track, i) => {
      const li = document.createElement("li");
      const num = document.createElement("span");
      num.className = "qnum";
      num.textContent = String(i + 1);
      const title = document.createElement("span");
      title.className = "qtitle";
      title.textContent = track.title;
      li.append(num, title);
      li.classList.toggle("active", i === idx);
      li.addEventListener("click", () => {
        void player.playIndex(i).catch(showError);
      });
      return li;
    }),
  );
  clearBtn.disabled = tracks.length === 0;
  const cur = player.current();
  const nowText = cur ? cur.title : "nothing playing";
  // Only re-measure the marquee when the title actually changes — render() also
  // fires on download start/stop, and re-measuring would restart the scroll.
  if (nowText !== nowEl.textContent) {
    nowEl.textContent = nowText;
    updateNowMarquee();
  }
  const status = player.getStatus();
  // Player status and download activity are independent indicators: the state
  // label is purely about playback ("idle" unless playing/paused/failed), while
  // the separate downloading indicator covers any in-flight fetch.
  stateEl.textContent =
    status === "playing" || status === "paused" || status === "failed"
      ? status
      : "idle";
  stateEl.classList.toggle("error", status === "failed");
  updateDownloadIndicator();
  const playing = audio.isPlaying();
  playPauseBtn.classList.toggle("is-playing", playing);
  const repeat = player.repeatMode();
  repeatBtn.classList.toggle("is-active", repeat !== "off");
  repeatBtn.classList.toggle("is-one", repeat === "one");
  repeatBtn.setAttribute("aria-label", `repeat ${repeat}`);
  repeatBtn.setAttribute("title", `repeat ${repeat}`);
  repeatBtn.setAttribute("aria-pressed", String(repeat !== "off"));
  document.documentElement.classList.toggle("playing", playing);
  if (playing) startFeedback();
  else stopFeedback();
  updateMediaSession();
}
player.onChange(render);

// "add" appends to the queue (the add row, Enter, and paste-to-add all use it);
// "replace" swaps the whole queue (the import button). One input feeds both.
let submitting = false;
async function submitUrl(mode: "add" | "replace"): Promise<void> {
  if (submitting) return;
  const url = urlInput.value.trim();
  if (!url) {
    urlInput.focus();
    return;
  }
  submitting = true;
  importBtn.disabled = true;
  if (mode === "add") addRow.classList.add("is-busy");
  setStatus(mode === "replace" ? "loading…" : "adding…");
  try {
    let added: number;
    if (mode === "replace") {
      await player.load(url);
      added = player.getQueue().length;
    } else {
      added = await player.add(url);
    }
    urlInput.value = "";
    if (mode === "add") flashAddRow();
    // Report just what this submit added, then let it fade — not the cumulative
    // queue length (confusing when adding a playlist onto an existing queue).
    if (added > 0)
      flashStatus(`queued ${added} track${added === 1 ? "" : "s"}`);
    else setStatus("");
  } catch (e) {
    showError(e);
  } finally {
    submitting = false;
    importBtn.disabled = false;
    addRow.classList.remove("is-busy");
  }
}

// one-shot glow on the add row so a paste/Enter visibly "lands"
function flashAddRow(): void {
  addRow.classList.remove("is-flash");
  void addRow.offsetWidth; // restart the animation
  addRow.classList.add("is-flash");
}

importBtn.addEventListener("click", () => void submitUrl("replace"));

// hold-to-clear: press and hold ~600ms to wipe the queue; releasing early
// cancels. Guards against an accidental one-tap nuke without a confirm modal.
(() => {
  const HOLD_MS = 600;
  let raf = 0;
  let start = 0;
  const setFill = (p: number): void =>
    clearBtn.style.setProperty("--clear-fill", `${p * 100}%`);
  const end = (): void => {
    cancelAnimationFrame(raf);
    raf = 0;
    clearBtn.classList.remove("is-arming");
    setFill(0);
  };
  const step = (t: number): void => {
    if (!start) start = t;
    const p = Math.min((t - start) / HOLD_MS, 1);
    setFill(p);
    if (p >= 1) {
      end();
      player.clear();
      return;
    }
    raf = requestAnimationFrame(step);
  };
  const begin = (e: Event): void => {
    if (clearBtn.disabled) return;
    e.preventDefault();
    start = 0;
    clearBtn.classList.add("is-arming");
    raf = requestAnimationFrame(step);
  };
  clearBtn.addEventListener("mousedown", begin);
  clearBtn.addEventListener("touchstart", begin, { passive: false });
  clearBtn.addEventListener("mouseup", end);
  clearBtn.addEventListener("mouseleave", end);
  clearBtn.addEventListener("touchend", end);
  // keyboard activation (Enter/Space) has no "hold"; clear directly. `detail===0`
  // marks a keyboard-synthesised click, so a mouse release here is a no-op.
  clearBtn.addEventListener("click", (e) => {
    if (e.detail === 0 && !clearBtn.disabled) player.clear();
  });
})();
// clicking the row chrome (not the input itself) focuses the field
addRow.addEventListener("click", (e) => {
  if (e.target !== urlInput) urlInput.focus();
});
urlInput.addEventListener("keydown", (e) => {
  if (e.key !== "Enter") return;
  e.preventDefault();
  void submitUrl("add");
});

// paste-to-add: drop a link anywhere (outside a text field) straight onto the
// queue, no clicking required.
document.addEventListener("paste", (e) => {
  if (document.activeElement instanceof HTMLInputElement) return;
  const text = e.clipboardData?.getData("text")?.trim();
  if (!text || !player.looksLikeUrl(text)) return; // ignore stray, non-URL text
  e.preventDefault();
  urlInput.value = text;
  void submitUrl("add");
});

function seekBy(delta: number): void {
  audio.seek(audio.currentTime() + delta);
}

playPauseBtn.addEventListener(
  "click",
  () => void player.togglePause().catch(showError),
);
prevBtn.addEventListener("click", () => void player.prev().catch(showError));
nextBtn.addEventListener(
  "click",
  () => void player.skipNext().catch(showError),
);
backBtn.addEventListener("click", () => seekBy(-SEEK_STEP));
fwdBtn.addEventListener("click", () => seekBy(SEEK_STEP));
repeatBtn.addEventListener("click", () => player.toggleRepeat());

scrubber.addEventListener("input", () => {
  seeking = true;
  updateSeekUI();
});
scrubber.addEventListener("change", () => {
  audio.seek(Number(scrubber.value));
  seeking = false;
});

function applyVolume(v: number): void {
  const clamped = Math.max(0, Math.min(v, 1));
  volumeInput.value = String(clamped);
  volumeInput.style.setProperty("--fill", `${clamped * 100}%`);
  audio.setVolume(clamped);
  if (audio.isMuted()) {
    audio.toggleMute(); // adjusting volume unmutes
    updateMuteIcon();
  }
}

volumeInput.addEventListener("input", () =>
  applyVolume(Number(volumeInput.value)),
);
muteBtn.addEventListener("click", () => {
  audio.toggleMute();
  updateMuteIcon();
});

bindKnob(speedKnob, speedInput, 50, 100, applyControls);
bindKnob(reverbKnob, reverbInput, 0, 100, applyControls);
bindSegment(reverbTypeGroup, (v) => audio.setReverbType(v as audio.ReverbType));
bindSegment(reverbCutoffGroup, (v) => audio.setReverbCutoff(Number(v)));

// ---- view nav + frameless window chrome ----------------------------------
const navButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>(".plate__nav .switch"),
);
const views = Array.from(document.querySelectorAll<HTMLElement>(".view"));
for (const btn of navButtons) {
  if (btn.disabled) continue;
  btn.addEventListener("click", () => {
    const v = btn.dataset.view;
    for (const b of navButtons)
      b.setAttribute("aria-selected", String(b === btn));
    for (const view of views)
      view.classList.toggle("is-active", view.dataset.view === v);
    if (v === "settings") startCachePoll();
    else stopCachePoll();
  });
}

// refetch the cache size each second while settings is open, so a download
// finishing (or any external change) shows up without reopening the view
let cachePollTimer = 0;
function startCachePoll(): void {
  void refreshCacheSize();
  window.clearInterval(cachePollTimer);
  cachePollTimer = window.setInterval(() => {
    if (!purgeBtn.disabled) void refreshCacheSize(); // don't fight the drain anim
  }, 1000);
}
function stopCachePoll(): void {
  window.clearInterval(cachePollTimer);
}

// ---- storage gauge (settings view) ---------------------------------------
const cacheNumEl = el<HTMLElement>("cacheSize");
const cacheUnitEl = el<HTMLElement>("cacheUnit");
const cacheMeterEl = el<HTMLElement>("cacheMeter");
const purgeBtn = el<HTMLButtonElement>("purgeCache");

// bar is full + reddest at 10 GiB; past that the number keeps climbing while
// the bar stays pinned full. nothing is enforced — it's a nudge, not a cap.
const CACHE_CAP = 10 * 1024 ** 3;
const METER_SEGMENTS = 16;
const METER_HOT_FROM = Math.round(METER_SEGMENTS * 0.75); // top quarter = red

const meterBars = Array.from({ length: METER_SEGMENTS }, () => {
  const bar = document.createElement("i");
  cacheMeterEl.appendChild(bar);
  return bar;
});

let cacheBytes = 0;

function fmtSize(bytes: number): [string, string] {
  const units = ["B", "KB", "MB", "GB"];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return [i === 0 ? String(Math.round(v)) : v.toFixed(1), units[i]];
}

function renderCache(): void {
  const fill = Math.min(1, cacheBytes / CACHE_CAP);
  const lit = Math.min(METER_SEGMENTS, Math.ceil(fill * METER_SEGMENTS));
  meterBars.forEach((bar, i) => {
    bar.className = i < lit ? (i >= METER_HOT_FROM ? "hot" : "on") : "";
  });
  const [val, unit] = fmtSize(cacheBytes);
  cacheNumEl.textContent = val;
  cacheUnitEl.textContent = unit;
  // ramp amber -> burgundy as it fills (reddest at the cap), biased to stay
  // warm until the back third so red only shows up when the cache is heavy
  const t = Math.pow(fill, 1.4);
  const r = Math.round(244 + (238 - 244) * t);
  const g = Math.round(186 + (106 - 186) * t);
  const b = Math.round(92 + (78 - 92) * t);
  cacheNumEl.style.color = `rgb(${r} ${g} ${b})`;
  cacheNumEl.style.textShadow = `0 0 11px rgb(${r} ${g} ${b} / 0.55)`;
}

async function refreshCacheSize(): Promise<void> {
  try {
    cacheBytes = await invoke<number>("cache_size");
  } catch (e) {
    cacheBytes = 0;
    console.debug("[cache] size failed:", e);
  }
  renderCache();
}

// count the readout down while bars wink out right-to-left
function drainMeter(done: () => void): void {
  const lit = meterBars.filter((bar) => bar.className).length;
  if (lit === 0) {
    done();
    return;
  }
  let killed = 0;
  for (let i = lit - 1; i >= 0; i--) {
    const delay = (lit - 1 - i) * 55;
    window.setTimeout(() => {
      meterBars[i].className = "";
      if (++killed === lit) done();
    }, delay);
  }
  const ms = Math.max(300, lit * 55);
  const start = performance.now();
  const step = (now: number): void => {
    const k = Math.min(1, (now - start) / ms);
    const [val, unit] = fmtSize(cacheBytes * (1 - k) ** 3); // easeOutCubic to 0
    cacheNumEl.textContent = val;
    cacheUnitEl.textContent = unit;
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

// two-step purge so a wipe is deliberate: arm -> confirm -> drain -> reset
let purgeArmed = false;
let purgeArmTimer = 0;
function disarmPurge(): void {
  purgeArmed = false;
  purgeBtn.classList.remove("is-armed");
  purgeBtn.textContent = "purge cache";
}
purgeBtn.addEventListener("click", () => {
  if (purgeBtn.disabled) return;
  if (!purgeArmed) {
    purgeArmed = true;
    purgeBtn.classList.add("is-armed");
    purgeBtn.textContent = "tap again to clear";
    purgeArmTimer = window.setTimeout(disarmPurge, 2600);
    return;
  }
  window.clearTimeout(purgeArmTimer);
  purgeArmed = false;
  purgeBtn.classList.remove("is-armed");
  purgeBtn.disabled = true;
  void invoke("purge_cache")
    .then(() => {
      player.forgetCaches(); // disk is gone; drop stale path/decode caches too
      drainMeter(() => {
        cacheBytes = 0;
        renderCache();
        purgeBtn.classList.add("is-empty");
        purgeBtn.textContent = "cache cleared";
        window.setTimeout(() => {
          purgeBtn.classList.remove("is-empty");
          purgeBtn.disabled = false;
          purgeBtn.textContent = "purge cache";
        }, 1500);
      });
    })
    .catch((e) => {
      purgeBtn.disabled = false;
      disarmPurge();
      showError(e);
    });
});

renderCache();

const win = appWindow();
winCloseBtn.addEventListener("click", () => void win.close());
winMinBtn.addEventListener("click", () => void win.minimize());
// The window is fixed-size, so zoom would only ruin the layout — disable it
// (the green dot greys out, like a macOS app that can't zoom).
winZoomBtn.disabled = true;
// The whole console is the window drag region (so empty space moves the
// window); interactive controls must not start a drag. One delegated handler
// covers static and dynamically-rendered (queue) controls alike.
const consoleEl = el<HTMLDivElement>("console");
consoleEl.addEventListener("mousedown", (e) => {
  const t = e.target as HTMLElement;
  if (t.closest('button, a, input, [role="slider"], .seg, .qlist li, .qadd'))
    e.stopPropagation();
});

// Keyboard basics. Skip when typing; otherwise handle globally and
// preventDefault so a focused control doesn't also react.
document.addEventListener("keydown", (e) => {
  if (e.defaultPrevented) return;
  const active = document.activeElement;
  if (active instanceof HTMLInputElement) return;
  switch (e.key) {
    case " ":
    case "k": // YouTube-style play/pause
      e.preventDefault();
      runMediaAction("playpause");
      break;
    case "ArrowLeft":
    case "j": // YouTube-style back 5s
      e.preventDefault();
      runMediaAction("back");
      break;
    case "ArrowRight":
    case "l": // YouTube-style forward 5s
      e.preventDefault();
      runMediaAction("fwd");
      break;
    case "ArrowUp":
      e.preventDefault();
      applyVolume(Number(volumeInput.value) + VOL_STEP);
      break;
    case "ArrowDown":
      e.preventDefault();
      applyVolume(Number(volumeInput.value) - VOL_STEP);
      break;
  }
  switch (e.code) {
    case "MediaPlayPause":
      e.preventDefault();
      runMediaAction("playpause");
      break;
    case "MediaTrackPrevious":
    case "MediaRewind":
      e.preventDefault();
      runMediaAction("prev");
      break;
    case "MediaTrackNext":
    case "MediaFastForward":
      e.preventDefault();
      runMediaAction("next");
      break;
  }
});

// Initial sync: control defaults into the engine, plus the seek ticker.
applyControls();
audio.setReverbType(selectedValue(reverbTypeGroup) as audio.ReverbType);
audio.setReverbCutoff(Number(selectedValue(reverbCutoffGroup)));
audio.setVolume(Number(volumeInput.value));
volumeInput.style.setProperty("--fill", `${Number(volumeInput.value) * 100}%`);
updateMuteIcon();
updateMediaSession();
// title width depends on the (async) font load and on breakpoint width changes
updateNowMarquee();
void document.fonts?.ready.then(updateNowMarquee);
addEventListener("resize", updateNowMarquee);
setInterval(updateSeekUI, 250);
// Keep the OS Now Playing scrubber moving (perceived seconds) without rebuilding
// the metadata dict each tick — that would re-load the artwork.
setInterval(() => {
  if (!audio.isPlaying()) return;
  void invoke("update_position", {
    positionSec: audio.currentTime() / (audio.speed() || 1),
    playing: true,
  });
}, 1000);

// ---- dev/test harness (inert without a hash) -----------------------------
// Forces UI view/state/queue with no network, e.g. `/#state=downloading`,
// `/#view=settings`, `/#queue=demo`. Drives both manual QA and Playwright.
function applyHarness(): void {
  if (!location.hash) return;
  const params = new URLSearchParams(location.hash.slice(1));

  if (params.get("queue") === "demo") {
    const titles = ["Resonance — HOME", "Snowfall — Øneheart", "i love you so"];
    queueEl.replaceChildren(
      ...titles.map((t, i) => {
        const li = document.createElement("li");
        li.textContent = t;
        li.classList.toggle("active", i === 0);
        return li;
      }),
    );
    nowEl.textContent = `${titles[0]} (slowed + reverb)`;
  }

  const view = params.get("view");
  if (view) {
    for (const b of navButtons)
      b.setAttribute("aria-selected", String(b.dataset.view === view));
    for (const v of views)
      v.classList.toggle("is-active", v.dataset.view === view);
  }

  const state = params.get("state");
  if (state) forceState(state);
}

function forceState(state: string): void {
  const playing = state === "playing";
  document.documentElement.classList.toggle("playing", playing);
  playPauseBtn.classList.toggle("is-playing", playing);
  stateEl.classList.toggle("error", state === "failed");
  // Mirror render()'s split: state label is playback-only, downloading is its
  // own indicator.
  stateEl.textContent =
    state === "playing" || state === "paused" || state === "failed"
      ? state
      : "idle";
  downloadingEl.textContent = state === "downloading" ? "downloading 42%" : "";
  if (state === "failed")
    statusEl.textContent =
      "ERROR: [youtube] video unavailable — Private video.";
  else statusEl.textContent = "";
  // light a static VU pattern for the playing snapshot
  for (const track of vuTracks) {
    const bars = track.children;
    const n = playing ? Math.ceil(bars.length * 0.6) : 0;
    for (let i = 0; i < bars.length; i++)
      bars[i].className = i < n ? (i >= bars.length - 2 ? "hot" : "on") : "";
  }
}

applyHarness();
addEventListener("hashchange", applyHarness);
