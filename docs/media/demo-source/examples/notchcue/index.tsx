import { useRef, type CSSProperties } from 'react'
import { AudioLines, BatteryFull, Mic, RotateCcw, Wifi } from 'lucide-react'
// Needs the Stageshow kit: see ../../README.md (docs/media/demo-source/README.md)
import { Roll, Stage, type Act } from '../../kit'
import './notchcue.css'

// NotchCue, the voice-following teleprompter, at the top of a MacBook screen.
// Copied from examples/dynamic-island: one black shape whose box (left, top,
// width, height, radius) springs between the notch and the panel, with the
// content on a separate layer that fades in once the shape is most of the way
// there. Words dimming in place borrow from examples/choreography: each word
// keeps its slot and only its color changes.
//
// Geometry is the app's own (PrompterContentView, PanelPreview, AppSettings)
// at 1.15x, so the README's 840px shows it near true size: a 32pt band, a 180pt
// notch, a 520 x 140 panel, 15pt text, ears inset 16, a 14pt progress ring.
//
// Real strings: the script, the pace readout, the timer, the live caption,
// "Off script", the menu bar's app menus and clock.

const K = 1.15
const W = 900
const H = 276
const CX = W / 2
const BAND = Math.round(32 * K) // 37, also the menu bar's height
const NOTCH_W = Math.round(180 * K) // 207
const PANEL_W = Math.round(520 * K) // 598
const BODY_H = Math.round(140 * K) // 161
const R_OPEN = Math.round(14 * K) // 16
const R_NOTCH = Math.round(12 * K) // 14

type Box = { l: number; w: number; h: number; r: number }
const NOTCH: Box = { l: CX - NOTCH_W / 2, w: NOTCH_W, h: BAND, r: R_NOTCH }
const OPEN: Box = { l: CX - PANEL_W / 2, w: PANEL_W, h: BAND + BODY_H, r: R_OPEN }

/** A damped spring as a CSS linear() easing (from examples/dynamic-island) */
function spring(zeta: number, omega: number, ms: number, n = 48) {
  const wd = omega * Math.sqrt(1 - zeta * zeta)
  const pts: string[] = []
  for (let i = 0; i <= n; i++) {
    const t = (i / n) * (ms / 1000)
    const x = i === n ? 1 : 1 - Math.exp(-zeta * omega * t) * (Math.cos(wd * t) + ((zeta * omega) / wd) * Math.sin(wd * t))
    pts.push(x.toFixed(4))
  }
  return `linear(${pts.join(', ')})`
}
// Grow: a small overshoot, settled by 0.55s. Shrink: no overshoot, a beat late
// so the content has cleared first.
const GROW = { ease: spring(0.72, 14, 550), ms: 550 }
const SHRINK = { ease: spring(0.98, 18, 400), ms: 400 }

// The script, as the app tokenizes it: words on spaces, a bracketed cue is a word
const SCRIPT =
  "This is NotchCue. [Pause] It's a tiny Mac app that hides your script right inside your camera notch, so you can look at the lens while you talk. See the difference?"
const WORDS = SCRIPT.split(' ')
const TOTAL = WORDS.length
const isCue = (w: string) => /^\[.*\]$/.test(w)

// What the speaker says, phrase by phrase. `from` is the script index of the
// phrase's first word; an ad-lib has none, and the panel holds.
type Phrase = { text: string; from: number | null }
const PHRASES: Phrase[] = [
  { text: 'This is NotchCue.', from: 0 },
  { text: "It's a tiny Mac app", from: 4 },
  { text: 'that hides your script', from: 9 },
  { text: 'right inside your camera notch,', from: 13 },
  { text: "and it's all offline,", from: null },
  { text: 'so you can look at the lens', from: 18 },
  { text: 'while you talk.', from: 25 },
  { text: 'See the difference?', from: 28 },
]
// Every word said, in order, as the caption hears them
const SPOKEN = PHRASES.flatMap((p) => p.text.split(' ').map((w) => ({ w, adlib: p.from === null })))
const FIRST = PHRASES.map((_, i) => PHRASES.slice(0, i).reduce((n, p) => n + p.text.split(' ').length, 0))
// The caption keeps the last few words: new ones open on the right as the
// oldest close on the left, so it is never empty mid-speech
const WINDOW = 5

const WPM = 164
type S = { open: boolean; idx: number; heard: number; chip: boolean; sec: number }
const START: S = { open: false, idx: 0, heard: 0, chip: false, sec: 0 }
// The poster: mid-sentence, the caption and the dimmed words meeting at "look at"
const POSTER: S = { open: true, idx: 23, heard: FIRST[5] + 5, chip: true, sec: 8 }

const mmss = (n: number) => `${Math.floor(n / 60)}:${String(Math.max(0, n) % 60).padStart(2, '0')}`

function Ring({ p }: { p: number }) {
  // One track and one arc, round caps, filling clockwise from 12 o'clock
  const r = 7
  return (
    <svg className="nc-ring" width="16" height="16" viewBox="0 0 16 16" aria-hidden>
      <circle cx="8" cy="8" r={r} className="nc-ring__track" />
      <circle cx="8" cy="8" r={r} className="nc-ring__arc" pathLength={1} strokeDasharray="1" style={{ strokeDashoffset: 1 - p }} />
    </svg>
  )
}

function Panel({ s }: { s: S }) {
  // Spring by direction, as the gold does: overshoot only when growing
  const last = useRef({ open: s.open, grow: true })
  if (last.current.open !== s.open) last.current = { open: s.open, grow: s.open }
  const grow = last.current.grow
  const b = s.open ? OPEN : NOTCH
  const shape: CSSProperties = {
    left: b.l,
    width: b.w,
    height: b.h,
    borderRadius: `0 0 ${b.r}px ${b.r}px`,
    transitionDuration: `${grow ? GROW.ms : SHRINK.ms}ms`,
    transitionTimingFunction: grow ? GROW.ease : SHRINK.ease,
    transitionDelay: grow ? '0ms' : '70ms',
  }
  const left = Math.ceil(((TOTAL - s.idx) * 60) / WPM)
  return (
    <div className="nc-panel">
      {/* The physical notch is always there; the panel grows out of it */}
      <span className="nc-notch" style={{ left: NOTCH.l, width: NOTCH.w, height: NOTCH.h, borderRadius: `0 0 ${R_NOTCH}px ${R_NOTCH}px` }} />
      <span className="nc-shape" style={shape} />
      {/* The camera, faint in the notch, there whether the panel is open or not */}
      <span className="nc-lens" style={{ left: CX - 4, top: BAND / 2 - 4 }} />
      <div className="nc-content" data-on={s.open || undefined} style={{ left: OPEN.l, width: OPEN.w, height: OPEN.h }}>
        <div className="nc-ear nc-ear--left" style={{ width: (PANEL_W - NOTCH_W) / 2 }}>
          <AudioLines className="nc-glyph" size={15} strokeWidth={2.1} absoluteStrokeWidth aria-hidden />
          <span className="nc-readout">
            <Roll>{`${WPM} wpm · ${mmss(left)} left`}</Roll>
          </span>
        </div>
        <div className="nc-ear nc-ear--right" style={{ width: (PANEL_W - NOTCH_W) / 2 }}>
          <span className="nc-readout">
            <Roll align="end">{mmss(s.sec)}</Roll>
          </span>
          <Ring p={s.idx / TOTAL} />
          <RotateCcw className="nc-glyph" size={15} strokeWidth={2.1} absoluteStrokeWidth aria-hidden />
        </div>
        <div className="nc-body" style={{ top: BAND, height: BODY_H }}>
          <p className="nc-script">
            {WORDS.map((w, i) => (
              <span key={i}>
                <span className="nc-word" data-cue={isCue(w) || undefined} data-read={(i < s.idx && !isCue(w)) || undefined}>
                  {w}
                </span>
                {i < WORDS.length - 1 ? ' ' : ''}
              </span>
            ))}
          </p>
        </div>
      </div>
    </div>
  )
}

/** Words as they are heard: each opens its own width as it sharpens in, so
 * the caption grows with the speech and never holds room for words unsaid */
function Heard({ count }: { count: number }) {
  return (
    <span className="nc-heard">
      {SPOKEN.map(({ w }, i) => (
        <span key={i} className="nc-heard__w" data-on={(i < count && i >= count - WINDOW) || undefined}>
          <span className="nc-heard__clip">
            <span className="nc-heard__t">{w}</span>
          </span>
        </span>
      ))}
    </span>
  )
}

function Caption({ s }: { s: S }) {
  const adlib = s.heard > 0 && SPOKEN[s.heard - 1].adlib
  return (
    <div className="nc-caption" data-on={s.chip || undefined} style={{ top: BAND + BODY_H - 18, left: OPEN.l + 16 }}>
      <Mic className="nc-caption__mic" size={14} strokeWidth={1.8} absoluteStrokeWidth aria-hidden />
      <span className="nc-caption__line">
        <Heard count={s.heard} />
      </span>
      {/* Opens its own width, so the chip hugs its words either way */}
      <span className="nc-caption__tagwrap" data-on={adlib || undefined}>
        <span className="nc-caption__tagclip">
          <span className="nc-caption__tag">Off script</span>
        </span>
      </span>
    </div>
  )
}

function MenuBar() {
  return (
    <div className="nc-menubar" style={{ height: BAND }}>
      <span className="nc-menubar__left">
        <span className="nc-menu nc-menu--app">Finder</span>
        <span className="nc-menu">File</span>
      </span>
      <span className="nc-menubar__right">
        <Wifi size={15} strokeWidth={1.8} absoluteStrokeWidth aria-hidden />
        <BatteryFull size={18} strokeWidth={1.6} absoluteStrokeWidth aria-hidden />
        <span className="nc-clock">Mon 9:41</span>
      </span>
    </div>
  )
}

const WORD_MS = 250
const LAG = 120 // recognition lands a hair after the word is said

/**
 * The loop, about 14s:
 *   0.3s  ⌃⌥⌘P, the app's start shortcut
 *   0.6s  the panel springs out of the notch; ears and script fade in after
 *   1.2s  the speaker starts; the caption shows each word as it is heard and
 *         the script dims up to it. The [Pause] cue holds the pace.
 *   5.3s  an ad-lib ("and it's all offline"): off script, the panel holds still
 *   6.6s  back on script, it resumes from the exact word
 *   9.8s  the last word; the ring closes, every word is dim. Held 1.9s.
 *  11.9s  ⌃⌥⌘H hides it: the caption and contents clear, it folds into the notch
 */
const script = async (a: Act<S>) => {
  let running = true
  a.mark('loop')
  await a.wait(250)
  a.mark('start')
  await a.key('ctrl+alt+cmd+p')
  a.put({ open: true })
  a.mark('open')
  // The timer, once a second while prompting
  void (async () => {
    while (running) {
      await a.wait(1000)
      if (running) a.put((s) => ({ sec: s.sec + 1 }))
    }
  })().catch(() => {})
  await a.wait(450)
  a.mark('speak')
  for (let pi = 0; pi < PHRASES.length; pi++) {
    const p = PHRASES[pi]
    const n = p.text.split(' ').length
    if (p.from === null) a.mark('adlib')
    for (let k = 0; k < n; k++) {
      // The caption arrives with the first word heard, never empty
      a.put({ chip: true, heard: FIRST[pi] + k + 1 })
      await a.wait(LAG)
      if (p.from !== null) {
        a.put({ idx: p.from + k + 1 })
      }
      await a.wait(WORD_MS - LAG)
    }
    if (pi === 0) {
      // The [Pause] cue: the reader takes it, the marker sits on it
      a.put({ idx: 4 })
      await a.wait(420)
    } else if (p.from === null) {
      await a.wait(220)
    } else {
      await a.wait(140)
    }
  }
  running = false
  a.mark('done')
  await a.wait(1900)
  a.mark('close')
  // The caption leaves with the speech; the panel's contents clear, then it folds
  a.put({ chip: false })
  await a.key('ctrl+alt+cmd+h')
  a.put({ open: false })
  await a.wait(550)
  // Hidden under the notch: back to the opening state
  a.snap({ ...START })
  await a.wait(100)
}

export default function NotchCue() {
  return (
    <Stage<S> width={W} height={H} initial={START} poster={POSTER} script={script} theme="dark" keys="bottom" className="nc">
      {(s) => (
        <div className="nc-desk">
          <div className="nc-wall" />
          <MenuBar />
          <Panel s={s} />
          <Caption s={s} />
        </div>
      )}
    </Stage>
  )
}
