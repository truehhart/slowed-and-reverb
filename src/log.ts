// Mirror the webview console into tauri-plugin-log, so the [player]/[audio]
// logs land in the terminal (where `mise run dev` runs) and the app logfile —
// not only in devtools. Tauri-only: in a plain browser tab the plugin isn't
// there, so we leave console alone.
import { isTauri } from "@tauri-apps/api/core";
import { trace, debug, info, warn, error } from "@tauri-apps/plugin-log";

type Level = "trace" | "debug" | "info" | "warn" | "error";

function stringify(a: unknown): string {
  if (typeof a === "string") return a;
  try {
    return JSON.stringify(a);
  } catch {
    return String(a);
  }
}

if (isTauri()) {
  const sinks: Record<Level, (m: string) => Promise<void>> = {
    trace,
    debug,
    info,
    warn,
    error,
  };
  // console.log has no log-level equivalent; fold it into info.
  const map: Record<string, Level> = {
    log: "info",
    trace: "trace",
    debug: "debug",
    info: "info",
    warn: "warn",
    error: "error",
  };
  for (const method of Object.keys(map)) {
    const orig = console[method as "log"].bind(console);
    console[method as "log"] = (...args: unknown[]) => {
      orig(...args);
      void sinks[map[method]](args.map(stringify).join(" ")).catch(() => {});
    };
  }
}
