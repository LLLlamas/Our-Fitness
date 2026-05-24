# CLAUDE.md — RepCheck

Mobile-first single-page tracker for daily bodyweight reps. **Fully self-contained single HTML file** — React + ReactDOM + compiled app code all inlined. Zero network requests at runtime (except web fonts, which are optional). Works via `file://`, `https://`, or anywhere. localStorage only.

## Why everything is inlined
Earlier versions used:
- `@babel/standalone` for in-browser JSX compilation → iOS Safari silently rejected `text/babel` script tags, leaving a blank "Loading…" screen.
- Tailwind CDN → noisy production warning, network dependency.
- React/ReactDOM via unpkg CDN → on `file://` URLs, iOS Safari treats CDN scripts as cross-origin and blocks them with an opaque "Script error." (this is the standard browser behavior, not a bug).

Fix: pre-compile JSX → plain JS, hand-write CSS, and inline React + ReactDOM directly into the HTML. The file now works no matter how you open it.

File size: ~168KB (React UMD bundles account for ~140KB).

## Goal
Log throughout the day with minimum friction (+1 / +5 / +10 per exercise). Review trends. No goal-setting, no nags — observation over prescription.

## Files
- `index.html` — entire app including inlined React 18 UMD bundles. No network needed at runtime.
- `test.js` — Node-runnable mirror of pure helpers. `node test.js`.
- `CLAUDE.md` — this file.

## Upgrading React
If you ever need to update React:
```bash
curl -sL https://unpkg.com/react@18/umd/react.production.min.js -o react.js
curl -sL https://unpkg.com/react-dom@18/umd/react-dom.production.min.js -o react-dom.js
```
Then replace the two `/* React 18 inlined */` and `/* ReactDOM 18 inlined */` `<script>` blocks in `index.html` with the new contents.
**Important:** when scripting this, don't use `String.replace` with the file content as the replacement string — `$` chars in the bundle get interpreted as backrefs and corrupt the source. Use `indexOf` + `slice`, or a function-style replacement.

## Editing the React code (if you want to change UI/logic)
The JS in `index.html` is the compiled output. You can either:
1. **Edit the plain JS directly inside `<script>...</script>`** — fine for small changes (it's still readable, just no JSX).
2. **Re-introduce a JSX source file and compile.** Steps:
   ```bash
   npm install --save-dev @babel/core @babel/cli @babel/preset-react
   # write app.jsx with JSX source
   npx babel app.jsx --presets=@babel/preset-react -o app.compiled.js
   # paste app.compiled.js into the <script> block in index.html
   ```
   Don't add @babel/standalone to the HTML — that's exactly what broke iOS Safari.

## Data model (localStorage key: `repcheck.v1`)
```
{
  sets: [{ id, exercise, count, timestamp }],   // append-only event log
  exercises: [{ id, label, unit, tab }]         // ordered, customizable
}
```
- All daily/weekly/streak totals are **derived** from `sets`. Never store rollups.
- `tab` is `'strength'` today; `'cardio'` reserved for Cardio tab.
- Day boundary = local midnight via `dayKey()`.

## Pure helpers (all in `index.html`, mirrored in `test.js`)
- `dayKey(ts)` → `YYYY-MM-DD` local
- `totalsForDay(sets, key)` → `{exerciseId: total}`
- `dailySeries(sets, exerciseId, days, endDate?)` → zero-filled array, oldest first
- `currentStreak(sets, exerciseId, endDate?)` → consecutive days ending today
- `allTimeTotal(sets, exerciseId)` → integer
- `formatTimeAgo(ts, now?)` → "5m ago"

**Do not** introduce a date library. Stay native.

## UI structure
- `App` → `Header` (tabs) → one of:
  - `TodayTab` → `ExerciseCard[]` — quick-log + per-exercise stats
  - `HistoryTab` → range toggle, per-exercise summary + `MiniBars` + optional `SetLog`
  - `CardioTab` — stub, expand later (running, mobility, prehab)
- `Footer` — export JSON, import JSON, run tests, wipe

## Adding an exercise
Edit `DEFAULT_EXERCISES` at top of `index.html`:
```
{ id: 'lunges', label: 'Lunges', unit: 'reps', tab: 'strength' }
```
Existing users: bump `STORAGE_KEY` to `repcheck.v2` and write a migration in `loadState`, OR add it via a UI later (TODO). For now, wipe + reimport.

## Adding a tab
1. Add to `tabs` array in `Header`.
2. Add a `{tab === 'newtab' && <NewTab .../>}` line in `App`.
3. If tab owns exercises, give them `tab: 'newtab'` and filter accordingly.

## Cardio tab — planned (not built)
- Sessions: `{ id, kind: 'run'|'bike'|..., durationMin, distanceKm?, notes?, timestamp }`
- Mobility / prehab: same set-based model as strength (reps or seconds).
- Likely re-use `ExerciseCard` for prehab; build a separate `SessionCard` for cardio.
- VO₂-relevant: keep duration + perceived effort (RPE 1–10) as separate fields.

## Testing
- `node test.js` — pure-logic tests (12 cases as of v1).
- In-app: footer `⌬ Tests` opens a modal with the same suite.
- Add tests for any new pure helper. Don't test React render.

## Deploy
GitHub Pages: drop `index.html` at repo root, enable Pages on `main`. No build.

## Gotchas
- `confirm()` dialogs are used for destructive ops. Replace with in-app modal if it gets annoying.
- Timestamps are `Date.now()` (UTC ms). Day grouping is local — be careful if you ever export/import across timezones.
- A global error trap in `<head>` renders any uncaught error to the screen instead of showing a blank page — leave this in.
- `data-type="module"` on a script tag breaks iOS Safari silently. Don't add it.
- Loading scripts from a CDN over `file://` URLs gives an opaque "Script error." on iOS Safari (cross-origin block). That's why React is inlined — don't re-introduce CDN script tags.

## Non-goals (v1)
- No accounts, no sync, no goals, no notifications, no PWA install (yet).
- Not multi-user. Not multi-device.

## Roadmap (sketch)
1. Cardio sessions + mobility/prehab in the Cardio tab.
2. Per-exercise notes on a set (form check, RPE).
3. Optional PWA manifest + service worker so it installs to home screen and works offline cleanly.
4. CSV export.
5. Goal lines on the history bars (opt-in, off by default — respects "no goals" v1 decision).
