#!/usr/bin/env node
// Render one loop of a stage to an animated GIF, frame-exact, with no ffmpeg.
//
//   node scripts/capture-gif.mjs "<preview>/?capture=notchcue" --out demo.gif \
//     [--width 840] [--fps 20] [--mark loop] [--colors 255]
//
// The kit's virtual clock (kit/clock.ts) is injected before the page loads, so
// time only moves when this script steps it: every frame lands at exactly
// 1000/fps ms. It records from the second time the stage's data-mark becomes
// --mark to the third, so the GIF's seam is the scene's own loop seam.
// Frames are screenshots of the stage at --width CSS px (device scale 1), then
// one global palette and transparent unchanged pixels keep the file small.
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { transformSync } from 'esbuild'
import { chromium } from 'playwright-core'
import { PNG } from 'pngjs'
import gifenc from 'gifenc'
const { GIFEncoder, quantize, applyPalette } = gifenc

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const url = args.find((a) => !a.startsWith('--') && !args[args.indexOf(a) - 1]?.startsWith('--'))
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`)
  return i >= 0 ? args[i + 1] : fallback
}
const out = resolve(opt('out', 'demo.gif'))
const width = Number(opt('width', 840))
const fps = Number(opt('fps', 20))
const mark = opt('mark', 'loop')
const colors = Number(opt('colors', 255))
const select = opt('select', '.ss-stage')
const dump = opt('dump', null) // a folder: also write every Nth frame as PNG to look at
const dumpEvery = Number(opt('dump-every', 10))
const CLOCK_FPS = 60
if (!url) throw new Error('usage: capture-gif.mjs <url> --out demo.gif')
if ((CLOCK_FPS / fps) % 1) throw new Error(`--fps must divide ${CLOCK_FPS}`)
const stepPerFrame = CLOCK_FPS / fps

// The clock installer, as plain JS for an init script
const src = readFileSync(resolve(root, 'kit/clock.ts'), 'utf8')
const fn = src.slice(src.indexOf('export function installVirtualClock')).replace(/^export /, '')
const { code } = transformSync(fn, { loader: 'ts' })
const init = `${code}\ninstallVirtualClock({ fps: ${CLOCK_FPS}, epoch: Date.UTC(2026, 10, 23, 17, 41) });`

const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' })
const page = await browser.newPage({ viewport: { width, height: 800 }, deviceScaleFactor: 1 })
page.on('pageerror', (e) => console.error('pageerror', e.message))
await page.addInitScript({ content: init })
await page.goto(url)
// Poll from here: the page's own timers and rAF are virtual now and never fire on their own
for (let i = 0; ; i++) {
  if (await page.evaluate((sel) => !!document.querySelector(sel) && !!window.__stageshow?.clock, select)) break
  if (i > 300) throw new Error(`no ${select} on the page`)
  await new Promise((r) => setTimeout(r, 100))
}
const step = (n) => page.evaluate((k) => window.__stageshow.clock.step(k), n)
const markNow = () => page.evaluate((sel) => document.querySelector(sel)?.getAttribute('data-mark') ?? '', select)
for (let i = 0; i < 30; i++) await step(1) // let fonts and layout settle

// Step one clock frame at a time until the mark has been entered `times` times
async function until(times) {
  let seen = 0
  let prev = await markNow()
  for (let guard = 0; guard < CLOCK_FPS * 120; guard++) {
    await step(1)
    const m = await markNow()
    if (m === mark && prev !== mark && ++seen === times) return
    prev = m
  }
  throw new Error(`mark "${mark}" not reached`)
}
await until(2)
const box = await page.locator(select).first().boundingBox()
const clip = { x: Math.ceil(box.x), y: Math.ceil(box.y), width: Math.floor(box.width), height: Math.floor(box.height) }

const frames = []
let prev = await markNow()
for (let guard = 0; guard < fps * 60; guard++) {
  const buf = await page.screenshot({ clip, animations: 'allow' })
  if (dump && frames.length % dumpEvery === 0) writeFileSync(resolve(dump, `f${String(frames.length).padStart(4, '0')}.png`), buf)
  const png = PNG.sync.read(buf)
  frames.push(png.data)
  await step(stepPerFrame)
  const m = await markNow()
  if (m === mark && prev !== mark) break
  prev = m
}
await browser.close()
const { width: w, height: h } = clip
console.log(`${frames.length} frames at ${fps} fps, ${w}x${h}, ${(frames.length / fps).toFixed(2)}s`)

// One palette for every frame, from a sample across the loop
const sampleEvery = Math.max(1, Math.floor(frames.length / 24))
const sample = []
for (let i = 0; i < frames.length; i += sampleEvery) sample.push(frames[i])
const all = new Uint8Array(sample.length * w * h * 4)
sample.forEach((f, i) => all.set(f, i * w * h * 4))
const palette = quantize(all, colors, { format: 'rgb565' })
const TRANSPARENT = palette.length
palette.push([255, 0, 255])

// A fixed 4x4 ordered dither (by pixel position, so still areas stay identical
// frame to frame and keep compressing) breaks up banding in dark gradients
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const dither = (rgba) => {
  const outp = new Uint8Array(rgba.length)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4
    const d = (BAYER[(y & 3) * 4 + (x & 3)] / 16 - 0.5) * 6
    for (let c = 0; c < 3; c++) outp[i + c] = Math.max(0, Math.min(255, Math.round(rgba[i + c] + d)))
    outp[i + 3] = 255
  }
  return outp
}

const gif = GIFEncoder()
let last = null
frames.forEach((rgba, i) => {
  const index = applyPalette(dither(rgba), palette.slice(0, TRANSPARENT), 'rgb565')
  if (last) {
    // Pixels whose palette index didn't change stay transparent: the previous frame shows through
    const shown = index.slice()
    for (let p = 0; p < index.length; p++) if (index[p] === last[p]) shown[p] = TRANSPARENT
    gif.writeFrame(shown, w, h, { palette, delay: 1000 / fps, transparent: true, transparentIndex: TRANSPARENT, dispose: 1 })
  } else {
    gif.writeFrame(index, w, h, { palette, delay: 1000 / fps, repeat: 0, dispose: 1 })
  }
  last = index
})
gif.finish()
writeFileSync(out, gif.bytes())
console.log(`${out}: ${(gif.bytes().length / 1024 / 1024).toFixed(2)} MB`)
