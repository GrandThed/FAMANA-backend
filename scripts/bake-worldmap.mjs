#!/usr/bin/env node
// Bakes the painted world zone map (pixel-art PNG) into a Luau data module
// so terrain generation follows the drawing pixel-faithfully.
//
//   node scripts/bake-worldmap.mjs new_art_style/map/reference/worldmap.png
//
// Legend (exact colors the map is painted with):
//   #3bd71b meadows          #ac8f42 hills            #616161 mountains
//   #a2b32d sand/beach       #a7c7f5 rivers           #5d7ba6 deep water
//   #deff3a cities           #ea00ff frontier walls   #72ffb1 stepping points
//   #000000 frontiers        red (~#ff0000) the rift
// Anything else (background, transparency) = "outside" -> open sea.
//
// Scale auto-calibrates from the largest city blob (defined as 300 studs
// across); world origin lands on that blob's centroid (= the spawn).
// Output: roblox/src/shared/WorldMapData.lua (zone grid + metadata).

import { inflateSync } from "node:zlib";
import { readFileSync, writeFileSync } from "node:fs";

const IN = process.argv[2] ?? "new_art_style/map/reference/worldmap.png";
const OUT = "roblox/src/shared/WorldMapData.lua";
const CITY_STUDS = 300; // the cell A village zone is 300 m across (1 stud = 1 m)

// ------------------------------------------------------------- png decode ---
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
  let width, height, bitDepth, colorType, pos = 8;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[12] !== 0) throw new Error("interlaced PNG unsupported");
      if (bitDepth !== 8 || (colorType !== 2 && colorType !== 6)) {
        throw new Error(`unsupported PNG format (bitDepth ${bitDepth}, colorType ${colorType}) — export as plain 8-bit RGB/RGBA`);
      }
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
    pos += 12 + len;
  }
  const bpp = colorType === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * bpp;
  const px = Buffer.alloc(width * height * 4);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0;
      const b = prev[i];
      const c = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      if (filter === 1) v = (v + a) & 0xff;
      else if (filter === 2) v = (v + b) & 0xff;
      else if (filter === 3) v = (v + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 0xff;
      }
      line[i] = v;
    }
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      px[o] = line[x * bpp];
      px[o + 1] = line[x * bpp + 1];
      px[o + 2] = line[x * bpp + 2];
      px[o + 3] = colorType === 6 ? line[x * bpp + 3] : 255;
    }
    prev = line;
  }
  return { width, height, px };
}

// ------------------------------------------------------------------ zones ---
// ids are stable API — WorldMap.lua matches them by name
const ZONES = [
  { id: 0, name: "outside" },
  { id: 1, name: "meadow", rgb: [0x3b, 0xd7, 0x1b] },
  { id: 2, name: "hills", rgb: [0xac, 0x8f, 0x42] },
  { id: 3, name: "mountains", rgb: [0x61, 0x61, 0x61] },
  { id: 4, name: "sand", rgb: [0xa2, 0xb3, 0x2d] },
  { id: 5, name: "river", rgb: [0xa7, 0xc7, 0xf5] },
  { id: 6, name: "deepwater", rgb: [0x5d, 0x7b, 0xa6] },
  { id: 7, name: "city", rgb: [0xde, 0xff, 0x3a] },
  { id: 8, name: "wall", rgb: [0xea, 0x00, 0xff] },
  { id: 9, name: "stepping", rgb: [0x72, 0xff, 0xb1] },
  { id: 10, name: "frontier", rgb: [0x00, 0x00, 0x00] },
  { id: 11, name: "rift", rgb: [0xff, 0x00, 0x00] },
];
const MATCH_DIST = 60; // per-channel-ish tolerance for slight AA/quantization

function classify(r, g, b, a) {
  if (a < 128) return 0;
  let best = 0, bestD = Infinity;
  for (const z of ZONES) {
    if (!z.rgb) continue;
    const d = Math.hypot(r - z.rgb[0], g - z.rgb[1], b - z.rgb[2]);
    if (d < bestD) {
      bestD = d;
      best = z.id;
    }
  }
  return bestD <= MATCH_DIST ? best : 0;
}

// ------------------------------------------------------------------- bake ---
const { width, height, px } = decodePng(readFileSync(IN));
const zones = new Uint8Array(width * height);
const counts = {};
for (let i = 0; i < width * height; i++) {
  const z = classify(px[i * 4], px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3]);
  zones[i] = z;
  counts[ZONES[z].name] = (counts[ZONES[z].name] ?? 0) + 1;
}
console.log(`${IN}: ${width}x${height}`, counts);

// largest city blob -> scale + origin (flood fill)
function blobs(zoneId) {
  const seen = new Uint8Array(width * height);
  const found = [];
  for (let i = 0; i < width * height; i++) {
    if (zones[i] !== zoneId || seen[i]) continue;
    const stack = [i];
    seen[i] = 1;
    let n = 0, sx = 0, sy = 0;
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    while (stack.length) {
      const j = stack.pop();
      const x = j % width, y = (j / width) | 0;
      n++; sx += x; sy += y;
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      for (const k of [j - 1, j + 1, j - width, j + width]) {
        if (k >= 0 && k < width * height && zones[k] === zoneId && !seen[k]) {
          seen[k] = 1;
          stack.push(k);
        }
      }
    }
    found.push({ n, cx: sx / n, cy: sy / n, w: maxX - minX + 1, h: maxY - minY + 1 });
  }
  return found.sort((a, b) => b.n - a.n);
}
const cities = blobs(7);
if (!cities.length) throw new Error("no city (#deff3a) pixels found — need one to calibrate scale");
const city = cities[0];
const studsPerPx = CITY_STUDS / Math.max(city.w, city.h);
console.log(`city blob: ${city.w}x${city.h}px at (${city.cx.toFixed(1)}, ${city.cy.toFixed(1)}) -> ${studsPerPx.toFixed(2)} studs/px`);

// world origin = city centroid (the spawn plateau)
const originPx = { x: city.cx, y: city.cy };

// ------------------------------------------------------------- luau emit ---
// zone bytes as \ddd-escaped Luau string chunks (4000 chars per chunk)
const chunks = [];
let cur = [];
for (let i = 0; i < zones.length; i++) {
  cur.push(`\\${zones[i]}`);
  if (cur.length === 4000) {
    chunks.push(cur.join(""));
    cur = [];
  }
}
if (cur.length) chunks.push(cur.join(""));

const lua = `-- GENERATED by scripts/bake-worldmap.mjs from ${IN.replace(/\\/g, "/")}
-- Do not edit by hand — repaint the map and re-bake.
-- Grid: ${width}x${height} px, ${studsPerPx.toFixed(4)} studs/px, row-major from
-- the image's top-left; world (0,0) = the main city centroid (spawn).
-- Zone ids: ${ZONES.map((z) => `${z.id}=${z.name}`).join(" ")}

local WorldMapData = {
	width = ${width},
	height = ${height},
	studsPerPixel = ${studsPerPx.toFixed(4)},
	originPx = { x = ${originPx.x.toFixed(2)}, y = ${originPx.y.toFixed(2)} },
	zones = table.concat({
${chunks.map((c) => `\t\t"${c}"`).join(",\n")},
	}),
}

return WorldMapData
`;
writeFileSync(OUT, lua);
console.log(`wrote ${OUT} (${(lua.length / 1024).toFixed(0)} KB)`);
