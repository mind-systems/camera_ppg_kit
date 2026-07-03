# camera_ppg_kit

> Flutter plugin that turns the phone's rear camera and flash into a contact-PPG heart-rate source for `mind_mobile`.

The user presses a fingertip over the camera lens and the flash; the LED lights the tissue, and the camera observes the pulsatile change in red-channel intensity. From that signal the kit produces a stream of **RR intervals** (the time between heartbeats, in milliseconds) together with a live signal-quality assessment. Higher-level numbers — BPM, HRV — are left to the consumer to derive from the intervals.

It is one heart-rate source among several the app integrates (alongside `neiry_kit` and future worn sensors). Each source ships as its own plugin and is consumed by `mind_mobile` behind a shared domain contract, so the camera source drops in the same way Neiry did. Internally it wraps the [`flutter_ppg`](https://pub.dev/packages/flutter_ppg) and [`camera`](https://pub.dev/packages/camera) packages and adds the parts those leave to the host: choosing the camera that sits next to the flash, torch control, warm-up, session duration, and quality-based acceptance.

## Requirements

A **real device** with a camera and a flash (torch). Simulators and emulators cannot provide either, so measurement does not work there. The technique needs a still fingertip for roughly 30–60 seconds to yield stable intervals — it is a deliberate "measure now" interaction, not ambient sensing.

On phones where the flash sits far from the active lens, a single fingertip may not cover both; the kit selects the sensor co-located with the LED and reports poor signal (with guidance) where the hardware cannot deliver one.

## Installation

```yaml
dependencies:
  camera_ppg_kit:
    path: ../camera_ppg_kit
```

The host works only with the Dart API exported from `package:camera_ppg_kit/camera_ppg_kit.dart`; the native layer and the wrapped packages stay hidden.

## Running the example

The `example/` app exercises the source end-to-end — camera permission, finger presence, signal quality, and live RR/BPM — and is the way to validate behaviour on real hardware before integrating.

```bash
flutter run            # run the example on a connected real device
```

## Status

The Dart API exported from `package:camera_ppg_kit/camera_ppg_kit.dart` is frozen as the drop-in RR-interval source surface: the measurement session's streams and state machine, the camera-coverage UX (listing lenses, pinning one, previewing the live texture, reading which lens is active), and the exported model types. `mind_mobile` can depend on this shape with zero churn. Growing the surface after the freeze is a deliberate, consciously-made act, not an incidental one — see the architecture document for the boundary the barrel enforces and which extras are debug-only.

## Consuming as a heart-rate source

Import only the barrel, `package:camera_ppg_kit/camera_ppg_kit.dart` — nothing under `lib/src/` is a supported import.

A `CameraPpgSession` exposes three broadcast streams a consumer subscribes to: RR intervals, a coarse signal-quality band, and the measurement's lifecycle state. The lifecycle moves `idle → warmup → measuring ⇄ poorSignal`, returning to `idle` once `stop()` is called; there is no terminal "done" state to wait for.

This source emits RR intervals only — no heart-rate or HRV stream. `flutter_ppg`'s underlying signal exposes RR and nothing else; any BPM or HRV number is a derivative of the interval stream, so the consumer computes it downstream rather than reading it from the kit. When a finger lifts or the signal quality drops, the RR stream simply goes silent — no zero-value or placeholder ticks, no exception — so a host relying on a silence-window fallback (falling back to another sensor after a timeout with no new interval) sees exactly that: silence. `RrInterval.isArtifact` is the single channel for flagging an individual beat as untrustworthy; there is no separate error channel for artifacts.

Tagging emitted intervals with a source identifier and registering this kit as one of several interchangeable heart-rate sources are both concerns of the consuming app, not this kit — `mind_mobile` owns that adapter layer entirely.

The optional tuning constructor parameters on `CameraPpgSession`, and the `debugSignalStream` output, are `[debug]`-labelled extras used by this repository's own example app for live tuning and signal inspection. They are not part of the supported drop-in contract described above — a consumer should not construct or read them.
