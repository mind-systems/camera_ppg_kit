# Example — Rebuild the Calibration Screen on the Widget Kit

**Date:** 2026-07-03
**Source:** example UX quality pass (note 25 kit); note 21 (calibration behavior — unchanged)

## Key Findings

- The calibration screen (note 21 — pure consumer, 60 s countdown recording via the committed recorder) works but is visually crude. Recompose it on note 25's kit.
- **Presentation only** — the countdown, recorder `start`/`stop`/`save`, `service.isMeasuring` gate, and screen-local `_recording`/`_recorded` flags all keep their behavior (note 21).

## Details

Recompose as a `ListView` of `SectionCard`s (note 25):

- **Countdown card** — large **monospace** `1:00 → 0:00` (headline); a `StatusChip`/`StateBanner` for the current `MeasurementState`/SQI so the tester sees the signal is good before trusting the count.
- **Precondition state** — when the source is not running (`!service.isMeasuring`), show a proper `AsyncEmpty`/guidance card ("Start measurement on the Source screen first"), not a silently disabled button with no explanation.
- **Record controls** — Start-recording / Stop as full-width semantic buttons; disabled state obvious.
- **Save card** — the counted-beats `TextField`, the Save button (enabled on `_recorded`), and the written path as `SelectableText` below it.

## Guards

- Recording/countdown/consumer logic unchanged — note 21 stands; visual recomposition only.
- Depends on note 25. Kit `lib/` untouched; recorder (note 20) untouched.

## Verify

- Calibration screen matches the neiry bar; countdown → record → Save still works; the "start the source first" guidance shows when nothing is running.
