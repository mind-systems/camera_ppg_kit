# Example — Rebuild the Streams Screen on the Widget Kit

**Date:** 2026-07-03
**Source:** example UX quality pass (note 25 kit); note 24 (rename Kit-API → Streams); note 22 (pure-consumer behavior — unchanged)

## Key Findings

- The Streams screen (the renamed Kit-API consumer, note 24) is a pure display of the live stream: RR + `isArtifact`, derived BPM, SQI, finger-presence, `MeasurementState`. Recompose it on note 25's kit to neiry's bar.
- **Presentation only** — it stays a `ref.watch`-only consumer (note 22); no lifecycle, no camera.

## Details

Recompose as a `ListView` of `SectionCard`s (note 25):

- **BPM card** — prominent large monospace number (`MetricRow` with `mono`, or a centered big `Text`), `'—'` when null. This is the headline metric.
- **Live-RR card** — latest interval + a short rolling list; artifact ticks visibly flagged (`StatusChip`/color, not filtered — the developer wants to see rejected beats, note 14).
- **Signal card** — SQI + finger-presence as `StatusChip`s.
- **`StateBanner`** for `MeasurementState`.
- **Async states** — real `.when` loading/empty so before signal the screen shows "waiting for signal…" (`AsyncEmpty`), not blank/stale values.

## Guards

- Consumer logic unchanged (note 22); no start/stop here.
- Depends on note 25 (widgets) **and** note 24 (the rename to `streams_screen.dart`/`StreamsScreen`).
- No `done`/"Complete" arm (note 23). Kit `lib/` untouched.

## Verify

- Streams screen shows live RR/BPM/SQI in neiry-style cards; artifact beats flagged; a "waiting for signal…" state before data.
