// Regenerate Resources/AppIcon.icns from Resources/icon.svg.
//
// Dev-only: the .icns is checked in, so building the app never needs this.
// A browser draws the SVG because ImageMagick's internal renderer drops
// strokes, and the mark is all strokes.
//
//   npm i -D playwright-core && npx playwright install chromium
//   node scripts/render-icon.mjs
import { readFileSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

let chromium;
for (const spec of ["playwright", "playwright-core"]) {
  try {
    ({ chromium } = await import(spec));
    break;
  } catch {}
}
if (!chromium) {
  console.error("needs playwright: npm i -D playwright-core && npx playwright install chromium");
  process.exit(1);
}

const svg = readFileSync(join(root, "Resources/icon.svg"), "utf8");
const iconset = join(root, "build/icon.iconset");
rmSync(iconset, { recursive: true, force: true });
mkdirSync(iconset, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 1024, height: 1024 },
  deviceScaleFactor: 1,
});
await page.setContent(`<body style="margin:0;background:transparent">${svg}</body>`, {
  waitUntil: "load",
});
const png = await page.screenshot({ omitBackground: true });
await browser.close();

const master = join(root, "build/icon_1024.png");
writeFileSync(master, png);

const sizes = [
  ["icon_16x16.png", 16], ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32], ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128], ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256], ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512], ["icon_512x512@2x.png", 1024],
];
for (const [name, px] of sizes) {
  execFileSync("sips", ["-z", String(px), String(px), master, "--out", join(iconset, name)], {
    stdio: "ignore",
  });
}

execFileSync("iconutil", ["-c", "icns", iconset, "-o", join(root, "Resources/AppIcon.icns")]);
execFileSync("sips", ["-z", "256", "256", master, "--out", join(root, "docs/icon.png")], {
  stdio: "ignore",
});
console.log("wrote Resources/AppIcon.icns and docs/icon.png");
