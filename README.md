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

Early stage: the plugin is scaffolded and depends on `flutter_ppg` + `camera`; the Dart API surface and native camera-selection bridges are being built out. The intended public shape and boundaries are described in the architecture document.

## Documentation

`CLAUDE.md` is the single source of truth for this repository. See also `.ai-factory/DESCRIPTION.md` for the specification and `.ai-factory/ARCHITECTURE.md` for the architecture and dependency rules.
