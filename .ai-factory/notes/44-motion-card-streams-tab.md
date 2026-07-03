# Motion card on the Streams tab — live raw values + real-time Hz

**Date:** 2026-07-03
**Source:** conversation context (see the raw motion stream and measure its rate)

## Goal

Surface the kit's raw motion stream (note 43) on the example's **Streams** tab: a new
card showing the live accel/gyro values **and a real-time sample-rate (Hz) counter**, so
the developer can watch the actual throughput and decide whether it needs throttling —
the concern being an unexpectedly high (~200 Hz) firehose vs the 5–10 Hz that would
suffice.

## Current state

`streams_screen.dart` is a pure `ref.watch` consumer with `_bpmCard`/`_rrCard`/
`_signalCard` (`SectionCard`s). The example service (`camera_ppg_service.dart`) fans the
session's streams into its own long-lived broadcast controllers via `_subs.addAll([...])`,
exposed through Riverpod providers in `stream_providers.dart`. `example/lib/common/fps_meter.dart`
already implements a rolling-window rate meter (`record(now)` + `fps` getter) used for the
frame path — directly reusable for a Hz counter.

## The change (example only)

- Service: add a `_motionController` (broadcast) and fan `session.motionStream` into it in
  `_subs.addAll([...])`, mirroring the existing bridges; expose a `motionProvider` in
  `stream_providers.dart`.
- Streams tab: a new `_motionCard` (`SectionCard` title "Motion") rendering the latest
  `MotionSample` — accel x/y/z and gyro x/y/z, monospace, live — plus a **Hz readout**
  driven by a `FpsMeter` instance: `record(sample.timestamp)` (or `DateTime.now()`) on
  each emit, display `meter.fps` as "N Hz". Shows a "waiting…" async state until the first
  sample. Ordered after the existing cards.

## Guards

- Example presentation only — no kit `lib/` change (that is note 43); no change to
  RR/quality logic.
- Reuse `FpsMeter` for the Hz counter — do not write a second rate-measuring helper.
- Consumer-only: `ref.watch`, no session control from this screen (Source owns lifecycle).

## Verify

- With a measurement running, the Motion card shows live accel/gyro numbers updating and a
  stable Hz reading; the Hz value reveals the device's actual motion sample rate (the
  number the throttling decision hinges on). On Stop the card returns to "waiting…".
