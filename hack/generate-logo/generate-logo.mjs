// Regenerates the slowed & reverb text logo at public/text-logo.svg.
//
// Output is self-contained: takumi bakes the Playfair Display glyphs into
// <path> outlines, so the SVG has no font or library dependency at runtime.
//
// Deps (pin to beta.6 — beta.8's native binding is NOT published on npm):
//   npm i takumi-js@2.0.0-beta.6 @takumi-rs/core@2.0.0-beta.6 \
//         @takumi-rs/helpers@2.0.0-beta.6 @takumi-rs/core-darwin-arm64@2.0.0-beta.6
// Run (needs network — fetches the Google font):
//   node hack/generate-logo/generate-logo.mjs
//
// takumi gotchas baked into this script: fromHtml does NOT decode HTML
// entities (use a literal "&", not &amp;) and does NOT support
// background-clip:text.
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { renderSvg } from "takumi-js";
import { googleFont } from "@takumi-rs/helpers";
import { Renderer } from "@takumi-rs/core";

const renderer = new Renderer();
for (const d of await googleFont("Playfair Display")) {
  await renderer.registerFont({
    name: d.name,
    weight: d.weight,
    style: d.style,
    data: Buffer.from(await d.data()),
  });
}

// Editorial serif wordmark, italic gold ampersand. Outer wrapper auto-sizes,
// so the SVG crops tight to the words + padding.
const html = `
  <div style="display:inline-flex;align-items:center;padding:48px 64px;">
    <div style="display:flex;align-items:baseline;font-family:'Playfair Display';font-weight:900;font-size:140px;color:#2a2320;">
      <span>slowed</span>
      <span style="font-weight:700;font-style:italic;font-size:120px;margin:0 24px;color:#b07d3c;">&</span>
      <span>reverb</span>
    </div>
  </div>`;

const svg = await renderSvg(html, { renderer });
const out = fileURLToPath(
  new URL("../../public/brand-text.svg", import.meta.url),
);
writeFileSync(out, svg);
console.log("wrote", out, `(${svg.length} bytes)`);
