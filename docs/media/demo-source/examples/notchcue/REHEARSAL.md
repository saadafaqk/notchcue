# Rehearsal: NotchCue README hero

Gold: `dynamic-island`. Kept: one black shape whose box (left, width, height, radius) springs between two presentations (underdamped grow, critically damped shrink a beat late), with the content as a separate unfiltered layer that fades in after the shape is mostly open. Changed: the phone and lock screen became a dark macOS desktop strip with a menu bar and the MacBook notch; the island became NotchCue's panel at the app's real geometry (PrompterContentView / PanelPreview / AppSettings: 32pt band, 180pt notch, 520 x 140 panel, 15pt text, 14pt ring, ears inset 16) scaled 1.15x; the goo filter and bud were dropped. From `choreography`: words keep their slots and only their color changes. The tap became the app's real hotkeys, ⌃⌥⌘P to start and ⌃⌥⌘H to hide, shown as keycaps.

Beats: ⌃⌥⌘P (0.3s), the panel springs out of the notch (0.6s), the voice is heard word by word in a live caption straddling the panel's foot and the script dims up to each word, the [Pause] cue holds (2s), an ad-lib "and it's all offline" marked Off script while the panel holds still (5.3s), back on script from the exact word, last word: every word dim, ring closed, timer stopped (held 1.9s), ⌃⌥⌘H folds it back into the notch. Loop 13.95s.
Stage 900 x 276, dark. Poster: mid-sentence, the caption "so you can look at" meeting the dim/bright frontier at "at". The GIF starts on the held payoff (cut at the `done` mark), so its first frame is settled.

Captured: the gate at the 900 design width only, not at 840 or 390; wide (900 design, filmed at 1280 viewport, 1:1) contact sheets at 500ms with `--gate`; `--states`; `--reduced` poster; the GIF capture at 840 wide, 20fps on the kit's virtual clock (frames inspected every 0.1 to 0.2s around open, ad-lib and close).
Gate: `rehearsal passed (necessary, not sufficient: references/verify.md and the fresh eye in review.md still stand)`
Film:
- `settle snap: span.ss-roll__mid … 19.9px` (and 110px in earlier runs) → the pace / timer Roll; `jumps.mjs` over 17s reports no jump, and the frames show no hop; left as is.
- `settle snap: div.nc-caption … 5.3px` / `lands on a transform` → the caption's entrance; the chip carries will-change on translate; not visible in 50ms frames.
- `near-empty frames … around 14.1s for 249ms` → the loop seam: the panel has folded into the notch (caused by ⌃⌥⌘H) and the next ⌃⌥⌘P follows within 0.35s; intentional.
- `manual: same-box content change: nc-ring` → the progress arc filling; intended.
Review (fresh-eye agent, run once, before these fixes; not re-run after them; 10 items) → response:
1. Generic, no lens or bezel → added the camera lens in the notch; the bezel is above the screen's top edge, so it stays out of this crop.
2. Empty lower desktop → stage cut from 360 to 296 to 276 tall; what is left holds the keycaps.
3. Empty black under 3 lines of script → kept: it is the app's real 140pt panel and this script is three lines long; the app's scroll math does not scroll a script shorter than the panel, so the reading line at 30% is not exercised (noted below).
4. No current-word mark → kept: the app marks read words at 35% and nothing else; the caption beside it carries the cause.
5. Placeholder menu bar → real menu titles ("Finder", "File") left of the panel's edge.
6. Close leaves a slab and an onion-skin chip → the caption now leaves first, the fold starts 70ms after the contents clear (was 140ms).
7. Dead stretch at the loop end → tail cut; the idle notch shows about 0.35s before ⌃⌥⌘P.
8. Blur smudges, tiny "Off script" → blur halved to 1.5px, "Off script" raised to 62% white.
9. Caption straddles the panel's edge → kept on purpose (framing.md rule 7: a satellite straddles its hero's edge, here over the panel's empty foot).
10. Ring reads like a spinner → kept: it is the app's real 14pt progress ring (track at 20% white, arc at 85%, round cap, from 12 o'clock).
Assumptions: the README countdown after ⌃⌥⌘P ("counts down") is left out for length; pace shown as a steady 164 wpm; "Off script" is a storytelling label in the caption, not app UI; the caption chip itself is a storytelling satellite, not app UI.
Unresolved: the catch-up-when-you-skip behavior is not shown.
Not checked: a 390 / compact design (a README has no phone column; at 390 the stage draws at 0.43 scale); light theme; live playback in the playground viewer (pause, resume, replay); real-time rAF pacing (the GIF uses the virtual clock); the GIF in GitHub's renderer (it was decoded and checked in headless Chrome).
