// Web Audio graph: tracks play through a dry/wet effect graph from a decoded
// AudioBufferSourceNode. playbackRate slows AND drops pitch (the slowed
// aesthetic); a ConvolverNode adds reverb.
//
//   AudioBufferSourceNode
//      ├─► dry ───────────────┐
//      │                      ├─► master ─► destination
//      └─► highpass ─► convolver ─► wet ───┘

import { convertFileSrc } from "@tauri-apps/api/core";

type Graph = {
  dry: GainNode;
  wet: GainNode;
  master: GainNode;
  reverbFilter: BiquadFilterNode;
  convolver: ConvolverNode;
  analyserL: AnalyserNode;
  analyserR: AnalyserNode;
};

export type ReverbType = "room" | "hall" | "plate";

type ReverbPreset = {
  seconds: number;
  decay: number;
};

const REVERB_PRESETS: Record<ReverbType, ReverbPreset> = {
  room: { seconds: 1.4, decay: 2.1 },
  hall: { seconds: 3, decay: 2.5 },
  plate: { seconds: 2.2, decay: 1.7 },
};

let ctx: AudioContext | null = null;
let graph: Graph | null = null;
let source: AudioBufferSourceNode | null = null;
let decoded: AudioBuffer | null = null;
// Position tracking: AudioBufferSourceNode has no currentTime, so we derive it
// from the context clock. On pause, stop the one-shot source and keep the saved
// offset; on resume, create a fresh source from that point.
let startOffset = 0;
let startedAt = 0;
let playbackSpeed = 0.85;
let wet = 0.6;
let reverbType: ReverbType = "hall";
let reverbCutoff = 80;
let volume = 1;
let muted = false;
let paused = false;
let onEnded: (() => void) | null = null;
const decodedCache = new Map<string, AudioBuffer>();
const MAX_DECODED_CACHE = 3;

// Decaying white noise — a cheap algorithmic reverb tail. No bundled IR asset.
function makeImpulseResponse(
  ac: AudioContext,
  preset: ReverbPreset = REVERB_PRESETS.hall,
): AudioBuffer {
  const { seconds, decay } = preset;
  const len = Math.floor(ac.sampleRate * seconds);
  const buf = ac.createBuffer(2, len, ac.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const data = buf.getChannelData(ch);
    for (let i = 0; i < len; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
    }
  }
  return buf;
}

function ensure(): { ac: AudioContext; g: Graph } {
  if (!ctx || !graph) {
    const ac = new AudioContext();
    ac.addEventListener("statechange", () => {
      console.debug("[audio] context state:", ac.state);
      // WKWebView suspends the AudioContext when another app takes the macOS
      // audio session (reported as "suspended"/"interrupted"). Auto-resume if
      // we're meant to be playing, else the app stays silent until restart.
      if (
        ac.state !== "running" &&
        ac.state !== "closed" &&
        !paused &&
        source
      ) {
        void ac.resume().catch(() => {});
      }
    });
    const convolver = ac.createConvolver();
    convolver.buffer = makeImpulseResponse(ac, REVERB_PRESETS[reverbType]);
    const reverbFilter = ac.createBiquadFilter();
    reverbFilter.type = "highpass";
    reverbFilter.frequency.value = reverbCutoff;
    const dry = ac.createGain();
    const wetNode = ac.createGain();
    const master = ac.createGain();
    dry.gain.value = 1;
    wetNode.gain.value = wet;
    master.gain.value = masterGain();
    // Read-only stereo bass taps: master → splitter → {L,R} low-pass → analysers.
    // They don't connect onward, so they never affect the audible signal. The
    // low-pass keeps each meter on the kick/bass band instead of the full mix,
    // so kicks (not vocals/hats) drive the reels.
    const splitter = ac.createChannelSplitter(2);
    const analyserL = ac.createAnalyser();
    const analyserR = ac.createAnalyser();
    analyserL.fftSize = 256;
    analyserR.fftSize = 256;
    // ponytail: single low-pass @ KICK_HZ — passes kick + bassline (can't fully
    // separate them without onset detection). Swap to a bandpass if rumble/bass
    // bleed becomes a problem.
    const bassL = ac.createBiquadFilter();
    const bassR = ac.createBiquadFilter();
    bassL.type = bassR.type = "lowpass";
    bassL.frequency.value = bassR.frequency.value = KICK_HZ;
    reverbFilter.connect(convolver);
    convolver.connect(wetNode).connect(master);
    dry.connect(master);
    master.connect(splitter);
    splitter.connect(bassL, 0).connect(analyserL);
    splitter.connect(bassR, 1).connect(analyserR);
    master.connect(ac.destination);

    ctx = ac;
    graph = {
      dry,
      wet: wetNode,
      master,
      reverbFilter,
      convolver,
      analyserL,
      analyserR,
    };
  }
  return { ac: ctx, g: graph };
}

function masterGain(): number {
  return muted || paused ? 0 : volume;
}

function applyMasterGain(): void {
  if (graph) graph.master.gain.value = masterGain();
}

// (Re)create the buffer source playing from `offset` seconds. Used by playPath
// (offset 0 or the URL timecode) and seek.
function startSource(offset: number): void {
  const { ac, g } = ensure();
  if (!decoded) return;
  const src = ac.createBufferSource();
  src.buffer = decoded;
  src.playbackRate.value = playbackSpeed;
  src.connect(g.dry);
  src.connect(g.reverbFilter);
  src.onended = () => {
    if (source === src) {
      source = null;
      onEnded?.();
    }
  };
  source = src;
  paused = false;
  applyMasterGain();
  startOffset = offset;
  startedAt = ac.currentTime;
  src.start(0, offset);
}

// Stop the current source without firing onEnded (clear `source` first so the
// onended guard skips it). Used by seek and before starting a new track.
function stopSource(): void {
  if (!source) return;
  const s = source;
  source = null;
  try {
    s.stop();
  } catch {
    // already stopped
  }
}

function rememberDecoded(path: string, buffer: AudioBuffer): void {
  // ponytail: tiny LRU; make this user-configurable only if memory reports say so.
  decodedCache.delete(path);
  decodedCache.set(path, buffer);
  while (decodedCache.size > MAX_DECODED_CACHE) {
    const oldest = decodedCache.keys().next().value;
    if (oldest === undefined) break;
    decodedCache.delete(oldest);
  }
}

/** Forget decoded buffers (e.g. after the on-disk cache is purged). The track
 * currently playing keeps its in-memory buffer, so playback isn't interrupted. */
export function clearDecodeCache(): void {
  decodedCache.clear();
}

/** Stop the current source immediately, without firing onEnded. */
export function stop(): void {
  stopSource();
  decoded = null;
}

/**
 * Play a local file; `startAt` (seconds) starts from a URL timecode.
 * `isCurrent` is checked after the async fetch/decode (which can outlive the
 * selection): if a newer track won meanwhile, we neither mutate `decoded` nor
 * start a source, so a stale decode can't resurrect overlapping audio.
 */
export async function playPath(
  path: string,
  startAt = 0,
  isCurrent: () => boolean = () => true,
): Promise<void> {
  const { ac } = ensure();
  let buffer = decodedCache.get(path) ?? null;
  if (buffer) {
    console.debug("[audio] decode cache hit:", path);
  } else {
    console.debug("[audio] fetching + decoding:", path);
    const res = await fetch(convertFileSrc(path));
    buffer = await ac.decodeAudioData(await res.arrayBuffer());
  }
  rememberDecoded(path, buffer);
  if (!isCurrent()) return; // a newer selection won during fetch/decode
  stopSource();
  decoded = buffer;
  startSource(Math.max(0, Math.min(startAt, decoded.duration)));
  paused = false;
  applyMasterGain();
  if (ac.state !== "running") await ac.resume();
}

/** Toggle playback. Returns true if now paused. */
export async function togglePause(): Promise<boolean> {
  if (!ctx || !decoded) return false;
  if (!paused && source) {
    startOffset = currentTime();
    paused = true;
    applyMasterGain();
    stopSource();
    return true;
  }
  if (!paused) return false;
  startSource(startOffset);
  if (ctx.state !== "running") await ctx.resume();
  return false;
}

export async function restart(): Promise<boolean> {
  if (!decoded) return false;
  stopSource();
  paused = false;
  startSource(0);
  if (ctx && ctx.state !== "running") await ctx.resume();
  return true;
}

export function setSpeed(value: number): void {
  // Rebase the position clock before changing rate, else the linear currentTime
  // formula would be wrong for the elapsed-at-old-speed portion.
  if (source && ctx) {
    startOffset = currentTime();
    startedAt = ctx.currentTime;
  }
  playbackSpeed = value;
  if (source) source.playbackRate.value = value;
}

export function speed(): number {
  return playbackSpeed;
}

export function setVolume(value: number): void {
  volume = value;
  applyMasterGain();
}

/** Toggle mute. Returns true if now muted. */
export function toggleMute(): boolean {
  muted = !muted;
  applyMasterGain();
  return muted;
}

export function isMuted(): boolean {
  return muted;
}

export function duration(): number {
  return decoded?.duration ?? 0;
}

export function currentTime(): number {
  if (!decoded || !ctx) return 0;
  if (paused) return startOffset;
  const t = startOffset + (ctx.currentTime - startedAt) * playbackSpeed;
  return Math.max(0, Math.min(t, decoded.duration));
}

/** Jump to `time` seconds, preserving the paused/playing state. */
export function seek(time: number): void {
  // Only seek a live or paused track. After a track ends, `source` is null and
  // `paused` is false, so this won't resurrect a finished track.
  if ((!source && !paused) || !decoded) return;
  const target = Math.max(0, Math.min(time, decoded.duration));
  if (paused) {
    startOffset = target;
    return;
  }
  stopSource();
  startSource(target);
}

export function setReverb(value: number): void {
  wet = value;
  if (graph) graph.wet.gain.value = value;
}

export function setReverbType(value: ReverbType): void {
  reverbType = value;
  if (ctx && graph) {
    graph.convolver.buffer = makeImpulseResponse(ctx, REVERB_PRESETS[value]);
  }
}

export function setReverbCutoff(value: number): void {
  reverbCutoff = value;
  if (ctx && graph) {
    graph.reverbFilter.frequency.setValueAtTime(value, ctx.currentTime);
  }
}

export function setOnEnded(cb: () => void): void {
  onEnded = cb;
}

export function isPlaying(): boolean {
  return !paused && source !== null && ctx?.state === "running";
}

const timeBuf = new Uint8Array(256);

// Per-channel meter envelope, for fast-attack / slow-release ballistics so
// transients punch the needle up and it eases back down.
let envL = 0;
let envR = 0;

// ponytail: ballistics + band/gain tuned by ear at ~60fps (getLevels runs once
// per rAF). Bump if a real calibration need shows up.
const KICK_HZ = 120; // low-pass cutoff for the bass taps — kick + bass fundamental
const METER_GAIN = 5; // makeup: the low-passed tap is far quieter than full-band
const ATTACK = 0.5; // close half the gap up to a louder reading each frame
const RELEASE = 0.1; // ...a tenth on the way down, so peaks stay readable

function meter(analyser: AnalyserNode, prev: number): number {
  analyser.getByteTimeDomainData(timeBuf);
  let sum = 0;
  for (let i = 0; i < timeBuf.length; i++) {
    const v = (timeBuf[i] - 128) / 128;
    sum += v * v;
  }
  const g = Math.sqrt(sum / timeBuf.length) * METER_GAIN;
  // Soft knee instead of a hard clamp: approaches 1 asymptotically, so a dense
  // full mix floats near the top with headroom left to wiggle, instead of
  // pinning flat at max. Low/mid levels stay ≈ linear, preserving the old feel.
  const target = 1 - Math.exp(-g);
  const k = target > prev ? ATTACK : RELEASE;
  return prev + (target - prev) * k;
}

/** Per-channel level, 0..1, for the VU meters. */
export function getLevels(): { l: number; r: number } {
  if (!graph) return { l: 0, r: 0 };
  envL = meter(graph.analyserL, envL);
  envR = meter(graph.analyserR, envR);
  return { l: envL, r: envR };
}
