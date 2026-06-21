# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`camera_ppg_kit` is a **Flutter plugin** that turns the phone's **rear camera + flash (torch)** into a heart-rate source via contact PPG (photoplethysmography): the user presses a fingertip over the lens and the LED, the camera observes the pulsatile change in red-channel intensity, and the kit emits a stream of **RR intervals** (inter-beat intervals, in milliseconds).

It is one **pulse source** among several the app will integrate (alongside `neiry_kit` and future BLE chest-straps, wearables, etc.). Each source ships as its own kit and is consumed by `mind_mobile` behind a domain contract — the app never talks to a vendor SDK directly.

The repo also contains an **example app** to exercise the source end-to-end (camera permission, finger-presence, signal quality, live RR/BPM) on real hardware **before** integrating into `mind_mobile`.

## Why a kit and not just `flutter_ppg` directly

The heavy lifting (red-channel extraction, bandpass, peak detection, RR-interval emission, signal-quality index) is done by the [`flutter_ppg`](https://pub.dev/packages/flutter_ppg) package, which this kit depends on. The kit exists to **wrap** that package behind the same shape `neiry_kit` exposes, so the source drops into `mind_mobile` the same way Neiry did:

- A small, idiomatic Dart API (`lib/camera_ppg_kit.dart` barrel) that hides `flutter_ppg`/`camera` details.
- Lifecycle and concerns that `flutter_ppg` explicitly leaves to the host: **which camera to use** (the one physically next to the torch), torch control, warm-up, session duration, acceptance gating, and quality-based artifact handling.
- Native platform code (`android/`, `ios/`) for anything Dart cannot do — primarily selecting the camera sensor co-located with the flash on multi-camera devices.

`mind_mobile` adds this kit as `path: ../camera_ppg_kit`, works only with its Dart API, and bridges it into the domain via an adapter in `lib/Biometrics/` (mirroring how `lib/Bci/NeiryBciProvider.dart` adapts `neiry_kit`). The adapter maps the kit's RR stream onto the existing **RR-interval source contract** (`docs/biometrics/active-rr-source.md` in `mind_mobile`), tagged as a `camera_ppg` source so the preferred-with-fallback policy can choose between camera and a worn device.

## What this source emits

- **RR intervals** (ms) — the primary output, physiologically bounded (~300–2000 ms). This is the same data type a chest-strap or `neiry_kit`'s PPG peak detector produces, so it maps onto the app's existing RR contract directly.
- **Signal Quality Index** (Good / Fair / Poor), SNR, finger-presence — drive the artifact/acceptance policy and the UI's "press your finger" guidance.
- **BPM and HRV metrics are NOT provided by the source** — the consumer computes them from the RR stream. Keep that boundary: the kit emits intervals + quality, nothing higher-level.

## Domain constraints that shape the design

- **Camera-near-flash selection is the central hardware problem.** On phones where the torch is far from the active lens, a single fingertip cannot cover both and the signal collapses. The kit must select the sensor co-located with the LED and degrade honestly (quality-gate + user guidance) where it cannot.
- **FPS sensitivity is high.** Heavy animations / frequent `setState` starve the frame stream and corrupt the signal. Measurement should run on a quiet screen, and frame processing should stay off the UI work — favour an isolate for the heavy path. Do not co-locate a live measurement with the breathing-session animation in the host app.
- **Contact PPG needs a still finger for 30–60 s** for stable intervals. It is unsuitable for motion / on-the-go capture. Treat it as a deliberate "measure now" interaction, not ambient sensing.

## Architecture (target shape — mirrors `neiry_kit`)

The kit follows the standard Flutter-plugin layout (`lib/camera_ppg_kit.dart` barrel re-exporting a `lib/src/` tree, plus `lib/camera_ppg_kit_platform_interface.dart` / `_method_channel.dart` for native calls). Inside `lib/src/`, organize by role as Neiry does:

- **`api/`** — the high-level Dart surface the host calls (start/stop a measurement session, subscribe to RR and quality streams, choose/override the camera).
- **`models/`** — value types crossing the API boundary (RR interval, signal quality, finger-presence, measurement state, errors).
- **`channel/`** — method/event-channel names and enums shared with native code.
- **`processing/`** — any Dart-side signal handling the kit adds on top of `flutter_ppg` (e.g. session acceptance, outlier policy) — analogous to Neiry's `ppg_peak_detector.dart`.

**Prior art to reuse:** `neiry_kit/lib/src/processing/ppg_peak_detector.dart` and `models/rr_interval.dart` already convert a raw PPG stream into RR intervals for the Neiry device. Read them before designing this kit's RR model and acceptance logic — keep the RR value type compatible so both sources feed the same host contract.

## Proto / contract ownership

This kit has **no proto contract** — it produces local biometric samples, not wire DTOs. The RR data only becomes a server concern inside `mind_mobile`'s `lib/Biometrics/` stream pipeline, which already owns that boundary. Do not add gRPC/proto here.

## Commands

```bash
# Run the example app on a real device (camera + torch are unavailable on simulators/emulators)
flutter run

# from the kit root, run the example explicitly:
flutter run -t example/lib/main.dart

# Tests
flutter test

# Add a dependency (never edit pubspec.yaml by hand)
flutter pub add <package_name>
```

> Always use `flutter pub add` to add packages — never edit `pubspec.yaml` manually.
> Use the full path `/usr/local/bin/flutter` when invoking Flutter from automation.

## Logging

This is a standalone plugin and does **not** depend on `mind_mobile`'s logger facade. Keep native/plugin logs minimal and behind a single internal helper (as Neiry does with `lib/src/util/nlog.dart`), so the host app's logging policy is not violated when the kit is embedded.

## Relationship to the rest of the monorepo

- Lives beside `neiry_kit/` under `/Users/max/projects/mind/` as a **separate git repository**. Run git operations inside this directory, not from the monorepo root.
- The monorepo root `.gitignore` ignores this folder (it is an independent repo).
- It is **not yet** wired into the root `.ai-factory/` orchestration — keep planning/notes local to this repo for now.
