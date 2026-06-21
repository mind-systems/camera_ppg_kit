# camera_ppg_kit

## Overview

`camera_ppg_kit` is a Flutter plugin that turns a phone's rear camera and flash (torch) into a contact-PPG heart-rate source. The user presses a fingertip over the lens and LED; the camera observes the pulsatile change in red-channel intensity, and the kit emits a stream of RR intervals (inter-beat intervals, in milliseconds) plus a signal-quality assessment.

It is one pulse source among several the `mind` app integrates (alongside `neiry_kit` and future BLE chest-straps and wearables). Each source ships as its own Flutter-plugin "kit" and is consumed by `mind_mobile` behind a domain contract — the app never talks to a sensor SDK directly. This kit wraps the [`flutter_ppg`](https://pub.dev/packages/flutter_ppg) package (camera-frame signal processing) and the [`camera`](https://pub.dev/packages/camera) plugin behind the same shape `neiry_kit` exposes, so the source drops into `mind_mobile` the same way Neiry did.

The repository also ships a single example app — a developer-facing playground (not an end-user measurement UX) for whoever integrates the kit. It exposes every kit capability on real hardware: a live inspector of all data streams (RR + artifact flag, derived BPM, signal quality, SNR, finger presence, measurement state, FPS) and a settings panel for every config knob (camera override, torch, warm-up/duration, acceptance-gate params), so the kit can be validated and tuned before wiring into `mind_mobile`.

## Core Features

- Contact-PPG measurement session over the rear camera + torch, emitting a live stream of RR intervals (ms).
- Per-measurement signal quality (Good / Fair / Poor), SNR, and finger-presence detection to drive acceptance and UI guidance.
- Signal-based camera auto-detect: the user covers whichever rear lens + flash is comfortable, and the kit detects which sensor was actually covered (via finger-presence/signal) and uses it. Honest degradation where no single fingertip can cover a lens and the flash together.
- Idiomatic Dart API hiding `flutter_ppg` / `camera` details, mirroring the `neiry_kit` surface for drop-in consumption.
- Single developer-playground example app (stream inspector + settings) for end-to-end validation and tuning on real devices before wiring into `mind_mobile`.

## Tech Stack

- **Programming language:** Dart (plugin) + Kotlin (Android) / Swift (iOS) for native camera-selection bridges
- **Framework:** Flutter (plugin template, `plugin_platform_interface` + method/event channels)
- **Key dependencies:** `flutter_ppg` (camera-frame PPG processing → RR intervals), `camera` (frame stream + torch control)
- **Database:** none — produces ephemeral biometric samples, not persisted here
- **Integrations:** consumed by `mind_mobile` via a `path:` dependency; bridged into the app's `lib/Biometrics/` RR-interval source contract, tagged `camera_ppg`

## Architecture Notes

Standard Flutter-plugin layout: a `lib/camera_ppg_kit.dart` barrel re-exporting a `lib/src/` tree, plus `camera_ppg_kit_platform_interface.dart` / `_method_channel.dart` for native calls. Inside `lib/src/`, code is organized by role mirroring `neiry_kit`: `api/` (high-level session/stream surface), `models/` (RR interval, signal quality, finger presence, measurement state, errors), `channel/` (channel names + enums), `processing/` (Dart-side acceptance / outlier policy layered on top of `flutter_ppg`).

`neiry_kit/lib/src/processing/ppg_peak_detector.dart` and `models/rr_interval.dart` are prior art — they already convert a raw PPG stream into RR intervals for the Neiry device. The RR value type stays compatible so both sources feed the same host contract.

This kit owns no proto/wire contract. RR data only becomes a server concern inside `mind_mobile`'s biometric stream pipeline, which already owns that boundary.

## Architecture

See `.ai-factory/ARCHITECTURE.md` for detailed architecture guidelines.
Pattern: Structured Modules (Technical Layers).

## Non-Functional Requirements

- **Hardware:** requires a real device with a camera and a flash (torch). Simulators/emulators cannot provide camera or flash and are unsupported for measurement.
- **Frame-rate sensitivity:** heavy UI work (animations, frequent rebuilds) starves the frame stream and corrupts the signal. Frame processing should stay off the UI work path (favour an isolate); measurement runs on a quiet screen, never co-located with the host's breathing-session animation.
- **Interaction model:** contact PPG needs a still finger for 30–60 s for stable intervals — a deliberate "measure now" interaction, not ambient sensing. Unsuitable for motion / on-the-go capture.
- **Error handling:** surface permission denial, no-finger / poor-signal, and unsupported-device states as typed model values, not exceptions across the channel boundary.
- **Logging:** standalone — does not depend on `mind_mobile`'s logger facade; keep internal logs behind a single helper so the host's logging policy is preserved when embedded.
