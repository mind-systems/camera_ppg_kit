# Project Roadmap

> Flutter plugin that turns the rear camera + flash into a contact-PPG heart-rate / RR-interval source for mind_mobile — one pulse source among several, consumed the same way `neiry_kit` is.

> Each phase below was a milestone derived from `neiry_kit`'s roadmap spine (scaffold → channel → models → API → native bridges → signal processing → example → service refactor → hardening → integration), now decomposed into atomic, independently-revertable tasks. Adapted to this kit: no vendored C SDK, and **camera selection is signal-based auto-detect** (the user covers a comfortable lens+flash, the kit detects which sensor was covered — note 01). Enumeration is Dart-side (note 03), so the native layer is **at most a torch-only fallback and is a deletion candidate**. `flutter_ppg` already does the signal DSP (red-channel, bandpass, peak detection, RR, SQI), so the kit's processing layer only ports neiry's *acceptance-gate* semantics on top. Specs for the spike-dependent later phases (native bridges, hardening, integration) are intentionally deferred until the Hardware-feasibility spike and a real `flutter_ppg`/`camera` exploration land — mirroring how neiry's bridge notes were written after SDK exploration.

## Phase 1 — Plugin scaffold

- [x] **Plugin scaffold** — Flutter plugin boilerplate, pubspec wired to `flutter_ppg` + `camera`, iOS/Android build configs, AI Factory context, standalone git repo + remote. (Complete — `7d3f86c`.)

## Phase 2 — Hardware feasibility spike

> The signal-based auto-detect reality check — gates the whole roadmap. Delivered as the **raw first panels of the single example app** (note 14 reconception), not a separate throwaway harness: a developer playground that, at this stage, only auto-detects the covered camera and renders the raw signal. Findings feed the native-bridge and hardening phases.

- [x] **Signal-based camera auto-detect** — the user places a finger over a comfortable rear lens + the flash and presses Start; the kit runs **one round-trip** over the rear sensors (torch on, short coverage dwell each, probe-order = most-likely-covered first) and locks the first that reads **covered** — finger-presence/coverage via `flutter_ppg`, not a confirmed pulse (cameras can't be opened concurrently, so the round-trip is sequential). If none is covered, surface a typed error and let the user retry. Build the auto-detect panel of the example app; establishes whether default-camera + finger-presence is enough. The rear-camera count per device is confirmed by a ~15-line `availableCameras()` probe — the *capability* is already known from plugin sources (note 03: iOS lists every rear lens, Android one logical back). Productionized in note 08; grows into the camera-override settings panel (note 08/14). Spec: `.ai-factory/notes/01-camera-enumeration-probe.md`. [23m 31s]
- [x] **flutter_ppg finger-video harness** — with a camera chosen by the probe, feed the `camera` `CameraImage` stream into `flutter_ppg`'s `FlutterPPGService.processImageStream` and render the raw `PPGSignal` output (RR intervals, SQI, SNR, finger-presence, detected FPS). The **raw stream-inspector panel** with no acceptance policy yet — establishes whether a usable signal exists per device and what FPS the frame path sustains under a static screen; grows into the full stream inspector (note 14). Spec: `.ai-factory/notes/02-flutter-ppg-harness.md`. [19m 56s]

---STOP---
- [ ] **Device-support matrix + go/no-go** — run the enumeration + raw-signal panels across the target device families and capture, per phone, whether a fingertip covers both lens and flash, achieved FPS, and RR stability vs a reference pulse. Produce a support matrix and an explicit go/no-go that decides whether camera PPG ships, and on which allow/deny-list of devices. Spec: `.ai-factory/notes/03-device-support-matrix.md`.

> **Everything below is gated by the Phase 2 go/no-go.** The hardware spike (notes 01/02/03) must run on real devices and produce a positive decision first: if it says shelve, or narrow the kit to an allow-list, the kit's shape — or whether it ships at all — changes, so building the channel contract, models, API, etc. beforehand risks throwing the work away. Phase 2 above *is* the hardware testing that yields the decision; do not start Phase 3 until the go/no-go says ship. (Phases 3–4 are pure Dart and need no device to *implement*, but they are still downstream of "is this kit worth building" — that is what the gate enforces.)

## Phase 3 — Dart channel contract

- [ ] **Channel names + enums** — the native layer needs a stable, tested name contract before bridges are written. Create `lib/src/channel/channel_names.dart` (`CameraPpgChannels` method-channel IDs for camera enumeration + torch, `CameraPpgEvents` event-channel IDs) and `lib/src/channel/enums.dart` (`MeasurementState`, `SignalQuality`, `CameraFacing` with int mappings); add unit tests asserting string uniqueness and enum int mappings. No bridge logic yet. Spec: `.ai-factory/notes/04-channel-contract.md`.

## Phase 4 — Dart models

- [ ] **Data value types** — the data path needs typed values before the API can stream them. Add `lib/src/models/rr_interval.dart` (`RrInterval { int intervalMs; DateTime timestamp; bool isArtifact }` — shape-identical to neiry's `RRInterval` so both sources feed one host contract) and `lib/src/models/signal_quality.dart` (`SignalQuality` Good/Fair/Poor + `double snr`, `fromSnr` factory). Export from the barrel; tests cover `fromMap` round-trips and `fromSnr` thresholds. Spec: `.ai-factory/notes/05-data-value-types.md`.
- [ ] **State & error types** — control/error surface, independently shippable from the data path. Add `lib/src/models/measurement_state.dart` (`MeasurementState` enum: idle/warmup/measuring/done/poorSignal), `lib/src/models/finger_presence.dart`, and `lib/src/models/camera_ppg_error.dart` (typed states for permission-denied / no-finger / unsupported-device — crossed as values, never thrown over the channel). Reuse the `orNull` sentinel pattern from neiry. Export + tests. Spec: `.ai-factory/notes/06-state-error-types.md`.

## Phase 5 — Dart API

- [ ] **CameraPpgSession + streams** — the high-level surface consumers call. Add `lib/src/api/camera_ppg_session.dart`: `start()`/`stop()` a measurement, broadcast `Stream<RrInterval> rrStream`, `Stream<SignalQuality> qualityStream`, `Stream<MeasurementState> stateStream`. Internally owns a `camera` `CameraController` feeding `flutter_ppg`'s `FlutterPPGService`; converts `PPGSignal` → kit models at this edge so `flutter_ppg`/`CameraImage` types never cross the barrel. Export from `lib/camera_ppg_kit.dart`. Spec: `.ai-factory/notes/07-camera-ppg-session.md`.
- [ ] **Camera auto-detect + override API** — by default `start()` runs signal-based auto-detect as a one-shot round-trip on Start (note 01: probe rear sensors in order, lock the first covered, else a typed `CameraPpgError` + retry), with zero host config. Consumers need a manual override for the rare device auto-detect mis-handles and for testing. Add `availableCameras()` (descriptive list: id + lens type + `flashAvailable`) + `useCamera(id)` (pin a camera, skip auto-detect) to the session. Spec: `.ai-factory/notes/08-camera-selection-api.md`.

## Phase 6 — Session policy

- [ ] **Warm-up / duration / acceptance gating** — `flutter_ppg` deliberately leaves session control to the host. Add a policy layer on `CameraPpgSession`: a warm-up window before RR is trusted, a target measurement duration, and acceptance/rejection driven by `SignalQuality` + finger-presence (emit `poorSignal` and guidance instead of bad intervals). Drives `MeasurementState` transitions. Spec: `.ai-factory/notes/09-session-policy.md`.

## Phase 7 — Native torch fallback (deletion candidate)

> Enumeration is Dart-side (note 03: iOS `availableCameras()` lists every rear lens, Android lists one logical back), so **no native enumeration is needed on either platform**. These tasks ship **only** if the Phase-2 spike finds the `camera` plugin's `setFlashMode(FlashMode.torch)` can't hold the torch during capture — a thin torch-only fallback. Default expectation: this phase is **deleted**.

- [ ] **iOS — torch fallback (only if needed)** — a single `setTorch` method channel in `ios/Classes/`; no enumeration. Spec: `.ai-factory/notes/10-ios-camera-selection-bridge.md`.
- [ ] **Android — torch fallback (only if needed)** — a single `setTorch` method channel; no enumeration; error parity with iOS. Spec: `.ai-factory/notes/11-android-camera-selection-bridge.md`.

## Phase 8 — Signal processing

- [ ] **RR acceptance gate (port from neiry)** — port `PpgPeakDetector`'s gate semantics into `lib/src/processing/rr_acceptance.dart`, applied to `flutter_ppg`'s already-detected intervals (flutter_ppg does the peak detection, so only the gate ports): hard 300 ms lower bound, no upper bound, rolling-median consistency filter (>40% deviation → artifact), cold-start grace for the first 3 beats. Sets `RrInterval.isArtifact`. Pure Dart, unit-tested without hardware. Spec: `.ai-factory/notes/12-rr-acceptance-gate.md`.
- [ ] **Isolate offload for the frame path** — move `flutter_ppg` frame processing off the UI work into an isolate so host animation cannot starve frames (the FPS-sensitivity risk from DESCRIPTION). Spec: `.ai-factory/notes/13-isolate-frame-offload.md`.

## Phase 9 — Example app (developer playground)

> The single `example/` app the kit ships — a developer-facing kitchen-sink, not an end-user measurement UX. Grows the Phase-2 raw panels into the full playground once the kit API/service exists.

- [ ] **Stream inspector + settings playground** — Riverpod + go_router app for the **developer integrating the kit**: live preview, a stream inspector showing every kit output raw (RR + `isArtifact`, derived BPM, SQI, SNR, finger-presence, `MeasurementState` as a value, FPS, optional waveform), and a settings playground exposing every config knob (camera override, torch, resolution/exposure, warm-up, target duration, gate params, raw-vs-gated). No session storyline, no end-of-session summary. Spec: `.ai-factory/notes/14-example-measurement-screen.md`.
- [ ] **Camera + runtime permissions** — request camera permission, handle denied/permanently-denied with settings deep-link; iOS `NSCameraUsageDescription`, Android runtime flow. Spec: `.ai-factory/notes/15-camera-runtime-permissions.md`.

## Phase 10 — CameraPpgService singleton

- [ ] **CameraPpgService device-layer singleton** — plain Dart service (no Flutter/Riverpod imports) owning the camera + `flutter_ppg` lifecycle behind broadcast streams, exposed via a Riverpod provider — mirrors neiry's `NeiryService` to avoid scattered lazy-init bugs. Spec: `.ai-factory/notes/16-camera-ppg-service-singleton.md`.

## Phase 11 — Plugin hardening

> Detail deferred until the example app surfaces real lifecycle crashes (cf. neiry's teardown-invariants work).

- [ ] **Lifecycle & teardown** — release camera + torch deterministically on dispose, app-background, and hot-restart; ensure the frame stream and isolate stop cleanly. Spec: `.ai-factory/notes/17-lifecycle-teardown.md`.
- [ ] **Permission / unsupported-device gating** — gate denied-permission and unsupported-device paths (from the Phase 2 deny-list) without crashes, surfacing `CameraPpgError` states. Spec: `.ai-factory/notes/18-permission-unsupported-gating.md`.

## Phase 12 — Integration readiness

- [ ] **Drop-in API freeze + docs** — finalize the barrel surface to match `mind_mobile`'s RR-interval source contract (tagged `camera_ppg`, preferred-with-fallback alongside worn sensors); consumer-facing README/docs. The actual `lib/Biometrics/` adapter lives in `mind_mobile`, not here. Spec: `.ai-factory/notes/19-drop-in-api-freeze.md`.
