// Single chokepoint for every Tauri IPC call. Outside Tauri (e.g. the plain
// Vite page in a browser tab) the wrappers no-op instead of throwing, so the UI
// boots headless and a missing/late IPC never hard-crashes the page.
import { invoke as rawInvoke, isTauri } from "@tauri-apps/api/core";
import type {
  EventCallback,
  EventName,
  UnlistenFn,
} from "@tauri-apps/api/event";
import { listen as rawListen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";

export { isTauri };

export function invoke<T>(
  cmd: string,
  args?: Record<string, unknown>,
): Promise<T> {
  // ponytail: off-Tauri callers (player.ts) gate on requireTauri() first, so an
  // undefined resolve here is only reached by harmless calls (cache lookup, opener).
  if (!isTauri()) return Promise.resolve(undefined as T);
  return rawInvoke<T>(cmd, args);
}

export function listen<T>(
  event: EventName,
  handler: EventCallback<T>,
): Promise<UnlistenFn> {
  if (!isTauri()) return Promise.resolve(() => {});
  return rawListen<T>(event, handler);
}

/** Window controls for the frameless chrome. No-op outside Tauri. */
export type WindowControls = {
  close(): Promise<void>;
  minimize(): Promise<void>;
  toggleMaximize(): Promise<void>;
};

const noopWindow: WindowControls = {
  close: async () => {},
  minimize: async () => {},
  toggleMaximize: async () => {},
};

export function appWindow(): WindowControls {
  return isTauri() ? getCurrentWindow() : noopWindow;
}
