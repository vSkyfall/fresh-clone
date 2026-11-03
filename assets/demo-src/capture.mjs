// capture.mjs: render scene.html frame by frame (deterministic time, not real time).
// Requires: npm i playwright-core, plus a Chromium (set CHROMIUM_PATH). Encode with ffmpeg, see README.md.
// Usage: node capture.mjs frames <fps> <outdir>      -> every frame
//        node capture.mjs stills <t1,t2,...> <outdir> -> a few checkpoints
import { chromium } from "playwright-core";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const [mode, arg, out] = process.argv.slice(2);
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const page = await browser.newPage({ viewport: { width: 1000, height: 640 }, deviceScaleFactor: 2 });
await page.goto("file://" + path.join(here, "scene.html"));
await page.evaluate(() => document.fonts.ready);
const stage = await page.$("#stage");
const duration = await page.evaluate(() => window.DURATION);

const times = mode === "stills"
  ? arg.split(",").map(Number)
  : Array.from({ length: Math.round(duration * Number(arg)) }, (_, i) => i / Number(arg));

for (let i = 0; i < times.length; i++) {
  await page.evaluate((t) => window.render(t), times[i]);
  const name = mode === "stills" ? `t${times[i]}.png` : `f${String(i).padStart(4, "0")}.png`;
  await stage.screenshot({ path: path.join(out, name) });
}
await browser.close();
console.log(`wrote ${times.length} images to ${out}`);
