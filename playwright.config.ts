import { defineConfig, devices } from "@playwright/test";

// Drives the plain Vite page (no Tauri, no yt-dlp) via the hash harness. The
// src/tauri.ts shim lets the page boot headless in the browser.
export default defineConfig({
  testDir: "tests/web",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: "list",
  use: {
    baseURL: "http://localhost:1420",
    trace: "on-first-retry",
  },
  // The app ships in WKWebView (macOS) — test the engine we actually run on.
  // Chromium-only runs hid a WebKit grid-overflow bug; don't reintroduce that.
  projects: [{ name: "webkit", use: { ...devices["Desktop Safari"] } }],
  webServer: {
    command: "pnpm dev",
    url: "http://localhost:1420",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
