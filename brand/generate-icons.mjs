#!/usr/bin/env node
/**
 * Benthyo / Benthio — brand icon generator.
 *
 * Single source of truth: brand/raw/logo-master.svg (512x512, navy bg,
 * bathymetric isolines). This script rasterizes that SVG into every size
 * the mobile app, the dashboard, and social/marketing need, using `sharp`.
 *
 * USAGE
 *   node brand/generate-icons.mjs
 *
 * OUTPUTS  (all under brand/generated/)
 *   mobile/
 *     icon-1024.png               — App Store / Play Store listing icon
 *     adaptive-foreground.png     — Android adaptive icon foreground (transparent bg, ~18% padding)
 *     adaptive-background.png     — Android adaptive icon background (solid navy)
 *   dashboard/
 *     favicon.svg                 — copy of the master SVG (modern browsers)
 *     favicon-32.png, favicon-16.png
 *     apple-touch-icon.png        — 180x180, opaque (iOS home screen)
 *     logo.svg                    — copy of master for sidebar use
 *     logo-mark.svg               — symbol only, transparent bg, tightly cropped
 *   social/
 *     og-image.png                — 1200x630 (Twitter/LinkedIn/WhatsApp preview)
 *     social-square.png           — 1024x1024 (store/press square)
 *
 * DEPENDENCY
 *   sharp — installed on the fly if missing (see ensureSharp()).
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const RAW = join(__dirname, 'raw');
const GEN = join(__dirname, 'generated');

const MASTER_SVG = join(RAW, 'logo-master.svg');

// ──────────────────────────────────────────────────────────────────────────
// Ensure sharp is available. Install it on the fly if missing (see ensureSharp),
// so this script stays self-contained and doesn't pollute any workspace.
// ──────────────────────────────────────────────────────────────────────────
async function ensureSharp() {
  // ESM cannot import a bare directory; sharp uses a package.json "exports"
  // map, so we resolve it via createRequire from each candidate location
  // (which honours exports) and then dynamic-import the resulting file URL.
  const candidateDirs = [
    process.cwd(),
    __dirname,
    join(__dirname, '.icon-tools'),
    ROOT,
  ];
  for (const dir of candidateDirs) {
    try {
      const require = createRequire(join(dir, 'noop.js'));
      const resolved = require.resolve('sharp');
      const mod = await import(pathToFileURL(resolved).href);
      return mod.default;
    } catch {
      /* try next candidate */
    }
  }
  // Bare specifier as a last resort (relies on NODE_PATH / cwd).
  try {
    return (await import('sharp')).default;
  } catch {
    /* install below */
  }
  process.stderr.write('sharp not found — installing transiently into brand/.icon-tools ...\n');
  const toolsDir = join(__dirname, '.icon-tools');
  if (!existsSync(join(toolsDir, 'package.json'))) {
    mkdirSync(toolsDir, { recursive: true });
    writeFileSync(
      join(toolsDir, 'package.json'),
      '{"name":"icon-tools","private":true,"type":"module","dependencies":{"sharp":"0.33.5"}}',
    );
  }
  const result = spawnSync(
    process.platform === 'win32' ? 'npm.cmd' : 'npm',
    ['install', '--no-audit', '--no-fund', '--prefix', toolsDir],
    { stdio: 'inherit' },
  );
  if (result.status !== 0) {
    throw new Error(
      'Failed to install sharp. Run manually:\n' +
        '  cd brand/.icon-tools && npm i sharp@0.33.5',
    );
  }
  const require = createRequire(join(toolsDir, 'noop.js'));
  const resolved = require.resolve('sharp');
  return (await import(pathToFileURL(resolved).href)).default;
}

// ──────────────────────────────────────────────────────────────────────────
// SVG variants
// ──────────────────────────────────────────────────────────────────────────

/**
 * Produce the "mark only" SVG: the isolines on a TRANSPARENT background,
 * tightly cropped (no navy fill, no rounded rect). Used for avatar-style
 * usages where the host provides its own background.
 *
 * We reuse the master's stroke paths but drop the background <rect> and
 * the clip path, and crop the viewBox to the drawn content.
 */
function buildMarkSvg(masterSrc) {
  // Extract the <g> ... </g> (the strokes). Keep the gradient def.
  const gMatch = masterSrc.match(/<g[\s\S]*?<\/g>/);
  const defsMatch = masterSrc.match(/<defs>[\s\S]*?<\/defs>/);
  if (!gMatch || !defsMatch) {
    throw new Error('Could not parse master SVG structure');
  }
  // Keep the linearGradient but drop the clipPath (we want unclipped marks).
  const defsInner = defsMatch[0]
    .replace(/<clipPath[\s\S]*?<\/clipPath>/, '')
    .replace(/clip-path="url\(#c\)"/, '');
  const gInner = gMatch[0].replace(' clip-path="url(#c)"', '');

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  ${defsInner}
  ${gInner}
</svg>
`;
}

/**
 * Build a composite PNG by compositing the foreground mark onto a solid
 * background at a target size with optional padding (for Android adaptive
 * icons, where the OS can mask and we must keep a safe zone).
 */
async function renderOnBg({ sharp, svgBuffer, size, bg, paddingPct = 0 }) {
  const innerSize = Math.round(size * (1 - paddingPct));
  const offset = Math.round((size - innerSize) / 2);

  const fg = await sharp(svgBuffer, { density: 384 })
    .resize(innerSize, innerSize, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  const composite = await sharp({
    create: {
      width: size,
      height: size,
      channels: 4,
      background: bg,
    },
  })
    .composite([{ input: fg, left: offset, top: offset }])
    .png()
    .toBuffer();

  return composite;
}

async function renderTransparent({ sharp, svgBuffer, size, paddingPct = 0 }) {
  const innerSize = Math.round(size * (1 - paddingPct));
  const offset = Math.round((size - innerSize) / 2);
  const inner = await sharp(svgBuffer, { density: 384 })
    .resize(innerSize, innerSize, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();

  return sharp({
    create: {
      width: size,
      height: size,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: inner, left: offset, top: offset }])
    .png()
    .toBuffer();
}

// ──────────────────────────────────────────────────────────────────────────
// Main
// ──────────────────────────────────────────────────────────────────────────
async function main() {
  if (!existsSync(MASTER_SVG)) {
    throw new Error(`Master SVG not found at ${MASTER_SVG}`);
  }

  const sharp = await ensureSharp();
  const masterSrc = readFileSync(MASTER_SVG, 'utf8');
  const masterBuf = Buffer.from(masterSrc);
  const markBuf = Buffer.from(buildMarkSvg(masterSrc));

  // Output dirs
  const dirs = ['mobile', 'dashboard', 'social'].map((d) => join(GEN, d));
  for (const d of dirs) mkdirSync(d, { recursive: true });

  const steps = [];

  // ── Mobile ────────────────────────────────────────────────────────────
  // App Store / Play Store listing icon: full logo on its own navy bg.
  steps.push(
    renderOnBg({ sharp, svgBuffer: masterBuf, size: 1024, bg: { r: 0x0f, g: 0x22, b: 0x38, alpha: 1 } })
      .then((buf) => writeFileSync(join(GEN, 'mobile', 'icon-1024.png'), buf)),
  );

  // Android adaptive icon — foreground (transparent bg, mark only, ~18% padding
  // safe zone as Google requires).
  steps.push(
    renderTransparent({ sharp, svgBuffer: masterBuf, size: 1024, paddingPct: 0.18 })
      .then((buf) => writeFileSync(join(GEN, 'mobile', 'adaptive-foreground.png'), buf)),
  );
  // Android adaptive icon — background (solid navy).
  steps.push(
    sharp({ create: { width: 1024, height: 1024, channels: 4, background: { r: 0x0f, g: 0x22, b: 0x38, alpha: 1 } } })
      .png()
      .toBuffer()
      .then((buf) => writeFileSync(join(GEN, 'mobile', 'adaptive-background.png'), buf)),
  );

  // ── Dashboard / web ───────────────────────────────────────────────────
  // Copy master SVG as favicon + sidebar logo (vector, infinitely scalable).
  copyFileSync(MASTER_SVG, join(GEN, 'dashboard', 'favicon.svg'));
  copyFileSync(MASTER_SVG, join(GEN, 'dashboard', 'logo.svg'));

  // apple-touch-icon: 180x180 opaque (iOS forces rounded corners itself,
  // and ignores transparency, so we render on solid navy).
  steps.push(
    renderOnBg({ sharp, svgBuffer: masterBuf, size: 180, bg: { r: 0x0f, g: 0x22, b: 0x38, alpha: 1 } })
      .then((buf) => writeFileSync(join(GEN, 'dashboard', 'apple-touch-icon.png'), buf)),
  );

  // Favicon PNGs (legacy browser fallback).
  for (const size of [32, 16]) {
    steps.push(
      renderOnBg({ sharp, svgBuffer: masterBuf, size, bg: { r: 0x0f, g: 0x22, b: 0x38, alpha: 1 } })
        .then((buf) => writeFileSync(join(GEN, 'dashboard', `favicon-${size}.png`), buf)),
    );
  }

  // Mark-only SVG (transparent) — for avatar / og / where host owns the bg.
  writeFileSync(join(GEN, 'dashboard', 'logo-mark.svg'), buildMarkSvg(masterSrc));

  // ── Social / marketing ────────────────────────────────────────────────
  // og-image 1200x630: centered mark on navy.
  const ogFg = await sharp(markBuf, { density: 384 })
    .resize(440, 440, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
  steps.push(
    sharp({
      create: { width: 1200, height: 630, channels: 4, background: { r: 0x0f, g: 0x22, b: 0x38, alpha: 1 } },
    })
      .composite([{ input: ogFg, left: 380, top: 95 }])
      .png()
      .toBuffer()
      .then((buf) => writeFileSync(join(GEN, 'social', 'og-image.png'), buf)),
  );

  // social-square 1024x1024: full logo (with its own navy bg, already rounded).
  steps.push(
    renderOnBg({ sharp, svgBuffer: masterBuf, size: 1024, bg: { r: 0x0f, g: 0x22, b: 0x38, alpha: 1 } })
      .then((buf) => writeFileSync(join(GEN, 'social', 'social-square.png'), buf)),
  );

  await Promise.all(steps);

  // Report
  const list = [
    'mobile/icon-1024.png',
    'mobile/adaptive-foreground.png',
    'mobile/adaptive-background.png',
    'dashboard/favicon.svg',
    'dashboard/favicon-32.png',
    'dashboard/favicon-16.png',
    'dashboard/apple-touch-icon.png',
    'dashboard/logo.svg',
    'dashboard/logo-mark.svg',
    'social/og-image.png',
    'social/social-square.png',
  ];
  process.stdout.write('\n✅ Generated brand assets:\n');
  for (const f of list) {
    const full = join(GEN, f);
    const ok = existsSync(full);
    process.stdout.write(`   ${ok ? '✓' : '✗'} ${f}\n`);
  }
  process.stdout.write('\nNext: wire these into apps/mobile and apps/dashboard (see brand/README.md).\n');
}

main().catch((err) => {
  console.error('❌ Icon generation failed:', err);
  process.exit(1);
});
