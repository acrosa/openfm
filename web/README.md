# OpenFM website

Landing page and interactive guide for [OpenFM](https://github.com/acrosa/openfm).

```sh
npm install
npm run dev      # http://localhost:3000
npm run build
```

- `app/page.tsx` — landing page
- `app/guide/page.tsx` — the guide: concepts, annotated screens, tutorial
- `components/Playground.tsx` — a two-operator FM synth in the browser
- `components/Song.tsx` — the tutorial's loop, played with Web Audio
- `components/Annotated.tsx` — numbered marks over a screenshot
- `public/screens/` — screenshots, captured from the simulator with `Tools/shot.sh`

The browser audio in `lib/fm.ts` is an illustration of FM, not the OpenFM engine.

Deploy on Vercel with the project's Root Directory set to `web`.
