// Pure UI math the knobs and clock depend on. Extracted from main.ts so it is
// directly unit-testable (no DOM, no audio).

export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(value, max));
}

/** mm:ss (clamps negatives / NaN to 0:00). */
export function fmt(t: number): string {
  if (!isFinite(t) || t < 0) t = 0;
  const m = Math.floor(t / 60);
  const s = Math.floor(t % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/** hh:mm:ss tape counter (clamps negatives / NaN to 00:00:00). */
export function fmtCounter(t: number): string {
  if (!isFinite(t) || t < 0) t = 0;
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = Math.floor(t % 60);
  return [h, m, s].map((n) => String(n).padStart(2, "0")).join(":");
}

/** Knob value → arc/dome sweep in degrees over the 270° range (0 at min). */
export function angleFromValue(
  value: number,
  min: number,
  max: number,
): number {
  const pct = (clamp(value, min, max) - min) / (max - min);
  return pct * 270;
}

/** Inverse of angleFromValue: a 0–270° sweep back to a rounded value. */
export function valueFromAngle(
  angle: number,
  min: number,
  max: number,
): number {
  const pct = clamp(angle, 0, 270) / 270;
  return Math.round(min + pct * (max - min));
}

/** 0–100 control value → 0–1 audio scalar (speed rate, reverb wet). */
export function pctToUnit(value: number): number {
  return value / 100;
}
