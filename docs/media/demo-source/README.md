# demo.gif source

`docs/media/demo.gif` and `docs/media/poster.png` are rendered from this scene. It is a
Stageshow scene (the Stageshow skill's React kit), and it needs that kit to run:
`examples/notchcue/index.tsx` imports `../../kit`, which is the kit folder of a Stageshow
working copy. Nothing here is part of the NotchCue app or its build.

## Re-render

1. In a Stageshow working copy (with `npm install` done), copy `examples/notchcue/` to
   `examples/notchcue/` and `scripts/capture-gif.mjs` to `scripts/`.
2. `npm i -D gifenc pngjs` in that copy (the capture script also uses `playwright-core` and
   `esbuild`, which Stageshow already has, and Google Chrome; set `CHROME_PATH` if it is not in
   `/Applications`).
3. `npm run dev`, then, with the preview's URL:

```sh
# the loop: 840 px wide, 20 fps, one loop from the scene's own seam
node scripts/capture-gif.mjs "<preview>/?capture=notchcue" --out demo.gif --width 840 --fps 20 --mark done
# the poster (the reduced-motion frame) at 2x
node scripts/film.mjs "<preview>/?capture=notchcue" --reduced --still --pad 0 --out poster.png
# the rehearsal gate
node scripts/film.mjs "<preview>/?capture=notchcue" --gate --every 500 --count 30 --out sheet.png
```

`capture-gif.mjs` injects the kit's virtual clock (`kit/clock.ts`) so every frame lands at an
exact 50 ms step, records one loop from the second time the scene reaches its `--mark` (here `done`, the held payoff, so the GIF opens on a settled frame) to the third, and encodes with one global
palette and transparent unchanged pixels.

`examples/notchcue/REHEARSAL.md` records what was checked and what was not.
