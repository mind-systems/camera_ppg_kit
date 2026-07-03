# Example lifecycle state machine — explicit transitional states + pure-consumer screens

**Date:** 2026-07-03
**Source:** conversation context (example UI bug report)

## Problem today

Measurement lifecycle in the example is implicit and scattered, which is why note 32's
bug existed at all and why the UI "hangs" during teardown:

- The only lifecycle signal is the kit's four-value `MeasurementState`
  (idle/warmup/measuring/poorSignal). There is **no representation of the async
  transitions** — the ~hundreds of ms of `start()` (probe round-trip, camera open) and
  of `stopMeasurement()` teardown (stop image stream → dispose isolate → torch off →
  dispose controller, which can be slow or hang on `camera_android_camerax`, see
  CLAUDE.md). During those windows the UI shows the *previous* state and its buttons in
  the wrong enabled/disabled combination, so a slow stop reads as a frozen "Measuring".
- Each screen re-derives `isRunning`/`canStop` from the raw enum
  (`source_screen.dart:126-129`) and the Raw branch pokes `stopMeasurement()` out of
  band, unawaited (`main.dart:88-104`). No single owner of "what is the source doing
  right now", so correctness depends on every call site agreeing.

## The change — one controller owns lifecycle; screens are pure consumers

Introduce an explicit lifecycle state machine in the **service** (the example's
composition root / controller layer), exposed as a single source of truth the screens
render directly:

- An example-side lifecycle enum (e.g. `SourceLifecycle`:
  `idle → starting → warmup → measuring ⇄ poorSignal → stopping → idle`) that **wraps**
  the kit's `MeasurementState` and adds the transitional `starting`/`stopping` states
  the kit contract deliberately does not carry. Keep it in the example
  (`services/`/`providers/`) — do NOT add transitional states to the kit's public
  `MeasurementState` (frozen, notes 19/23).
- `CameraPpgService` sets `starting` synchronously when `startMeasurement()` is entered
  and `stopping` synchronously when `stopMeasurement()` is entered, then folds the kit's
  `MeasurementState` stream through while running, and lands on `idle` when teardown
  completes (subsuming note 32's authoritative-idle push). Expose it as one
  `lifecycleProvider` the screens watch.
- Screens become pure consumers: the Source **Start** button is enabled only in `idle`,
  **Stop** only in `warmup`/`measuring`/`poorSignal`, and both render a disabled +
  spinner state during `starting`/`stopping` — so a slow or hanging teardown shows
  honest "Stopping…" progress instead of a frozen active state. The Raw-entry stop and
  every other call site route through the same lifecycle path, so no navigation leaves
  stale state.

## Relationship to note 32

Note 32 is the minimal unstick (guarantee the terminal `idle` arrives) and ships first.
This task is the structural fix that makes the whole class of bug impossible and gives
the operator honest feedback during async transitions. If note 32 already shipped, its
direct-idle push is absorbed into the `stopping → idle` transition here.

## Verify

- Start shows **Starting…** (disabled controls + spinner) until the first kit state
  (warmup) arrives; Stop shows **Stopping…** until teardown completes, then **Idle**.
- On a device where teardown is slow, the UI shows **Stopping…** for its full duration
  and then clears to Idle — it never shows a frozen "Measuring", and it never lets Start
  fire mid-teardown (the accepted Raw race in `main.dart:91-102` is closed by gating on
  lifecycle instead of firing unawaited).
- Repeated rapid Start/Stop and tab-switching never desync the buttons from the actual
  source state.

## Guards

- Example only — kit `lib/` and the public `MeasurementState`/`CameraPpgSession`
  untouched (Phase-10 freeze).
- Do not reintroduce a `done`/"Complete" state (note 23); `stopping → idle` is the
  terminal path.
- Keep the kit-side teardown invariant (close input bridge before cancelling the
  subscription, notes 07/13) — this task changes example lifecycle representation, not
  the kit teardown order.
