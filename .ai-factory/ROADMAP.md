# Project Roadmap

> Flutter plugin that turns the rear camera + flash into a contact-PPG heart-rate / RR-interval source for mind_mobile — one pulse source among several, consumed the same way `neiry_kit` is.

> Milestones follow `neiry_kit`'s spine (scaffold → models → API → policy → signal processing → example → service → hardening → integration), decomposed into atomic, independently-revertable tasks. Kit specifics: no vendored SDK; **camera selection is signal-based auto-detect** (note 01); **the Phase-2 spike (GO, note 03) confirmed the kit needs no native code** — enumeration is `availableCameras()` and the torch holds through capture via `setFlashMode(FlashMode.torch)`, so the former native channel-contract and torch-fallback phases are dropped. `flutter_ppg` does the DSP (red-channel, bandpass, peak detection, RR, SQI), so the kit's processing only layers neiry's *acceptance-gate* on top. The one remaining native concern — optional torch-brightness control — is deferred behind the STOP marker.

## Phase 1 — Plugin scaffold

- [x] **Plugin scaffold** — Flutter plugin boilerplate, pubspec wired to `flutter_ppg` + `camera`, iOS/Android build configs, AI Factory context, standalone git repo + remote. (Complete — `7d3f86c`.)

## Phase 2 — Hardware feasibility spike

> The signal-based auto-detect reality check — gated the whole roadmap. Delivered as the **raw first panels of the single example app** (note 14 reconception), not a throwaway harness. Findings fed the model/API/processing/hardening specs.

- [x] **Signal-based camera auto-detect** — finger-first-then-Start: on Start the kit runs one sequential round-trip over the rear sensors (torch on, short coverage dwell each, most-likely-covered first) and locks the first that reads **covered** via `flutter_ppg` finger-presence; no covered sensor → typed error + retry. Built as the auto-detect panel of the example app. Spec: `.ai-factory/notes/01-camera-enumeration-probe.md`. [23m 31s]
- [x] **flutter_ppg finger-video harness** — feed the chosen camera's `CameraImage` stream into `FlutterPPGService.processImageStream` and render the raw `PPGSignal` (RR, SQI, SNR, finger-presence, FPS). The raw stream-inspector panel, no acceptance policy yet. Spec: `.ai-factory/notes/02-flutter-ppg-harness.md`. [19m 56s]
- [x] **Example-panel teardown fix + interaction logging** — first on-device run (A70) froze with the torch stuck on: teardown awaited `StreamSubscription.cancel()` while `flutter_ppg`'s `async*` `processImageStream` was parked on `await for` over an open input — a deadlock. Fixed by closing the input `StreamController` **before** cancelling the subscription (both teardown paths); fixed an inspector `RenderFlex` overflow; established the example logging convention (`ppgTap` per button, coarse milestones, one helper) in CLAUDE.md. This close-before-cancel order is the load-bearing teardown invariant (carried into note 07/17).
- [x] **Device-support matrix + go/no-go** — ran the panels on the A70 and recorded the first matrix row. **Go/no-go = GO**: SQI `good`, ~24 FPS stable, plausible resting RR ~57–60 BPM — a usable contact-PPG signal exists on real hardware, so the kit proceeds to implementation. Findings: torch holds via `setFlashMode` (native fallback dropped), peak-halving artifacts (→ acceptance gate), FPS-quantized RR (~42 ms, HRV coarse). Matrix stays provisional; wider coverage folds into hardening. Spec: `.ai-factory/notes/03-device-support-matrix.md`.

> **Gate passed — go/no-go = GO (note 03).** The Phase-2 spike ran on real hardware and the kit ships; Phases 3+ below are open for implementation. Wider device coverage and any deny-list fold into hardening (note 18), not a re-gate.

## Phase 3 — Dart models

- [x] **Data value types** — add `lib/src/models/rr_interval.dart` (`RrInterval { int intervalMs; DateTime timestamp; bool isArtifact }`, shape-identical to neiry's `RRInterval` so both sources feed one host contract) and `lib/src/models/signal_quality.dart` (`SignalQuality` good/fair/poor + `fromSnr` factory). No BPM/HRV fields — the consumer derives those. Export from the barrel; unit-test `fromSnr` thresholds. Spec: `.ai-factory/notes/05-data-value-types.md`. [13m 41s]
- [x] **State & error types** — add `MeasurementState` (idle/warmup/measuring/done/poorSignal), `FingerPresence` (present/absent/over-bright), and a typed, never-thrown `CameraPpgError` (permission-denied / no-finger / unsupported-device / torch-unavailable). Pure Dart, crossed as values not exceptions. Export + tests. Spec: `.ai-factory/notes/06-state-error-types.md`. [28m 53s]

## Phase 4 — Dart API

- [x] **CameraPpgSession + streams** — the public surface (`lib/src/api/camera_ppg_session.dart`): `start()`/`stop()`, broadcast `rrStream`/`qualityStream`/`stateStream`. Owns a `CameraController` (`ResolutionPreset.low`, bgra8888/yuv420, torch via `setFlashMode` — no native) feeding `flutter_ppg` through a `StreamController<CameraImage>` bridge; converts `PPGSignal`→kit models at the edge so no `flutter_ppg`/`camera` type crosses the barrel. Teardown closes the input bridge before cancelling the subscription (the async* deadlock). Spec: `.ai-factory/notes/07-camera-ppg-session.md`. [49m 13s]
- [x] **Camera auto-detect + override API** — `start()` runs the signal-based round-trip by default (lock first covered sensor, else a typed `CameraPpgError`); add `availableCameras()` (descriptive rear list) + `useCamera(id)` to pin one and skip auto-detect. Android exposes one logical back, iOS every lens — same code, different breadth. Spec: `.ai-factory/notes/08-camera-selection-api.md`. [22m 12s]

## Phase 5 — Session policy

- [x] **Warm-up / duration / acceptance gating** — policy layer on `CameraPpgSession`: a warm-up window before RR is trusted, a target duration, and SQI + finger-presence acceptance (emit `poorSignal` + guidance instead of bad intervals), driving `MeasurementState`. On by default with concrete spike-tunable defaults; the host renders state, never reimplements the lifecycle. Spec: `.ai-factory/notes/09-session-policy.md`. [29m 50s]

## Phase 6 — Signal processing

- [x] **RR acceptance gate (port from neiry)** — `lib/src/processing/rr_acceptance.dart`: layer neiry's `_gate()` on top of flutter_ppg's intervals — hard 300 ms floor, no upper bound, rolling-median consistency (>40% deviation → artifact), 3-beat cold-start grace; sets `RrInterval.isArtifact`. The spike showed peak-halving leaks past flutter_ppg's own outlier filter (RR ~458 ms vs ~1040 ms median), which this catches. Pure Dart, unit-tested. Spec: `.ai-factory/notes/12-rr-acceptance-gate.md`. [8m 39s]
- [x] **Isolate offload for the frame path (defensive)** — `lib/src/processing/frame_message.dart` (pure sendable `FrameMessage`/`SignalMessage` types) + `frame_isolate.dart` (the `CameraImage`<->`FrameMessage` adapters and `FrameIsolate`, a long-lived spawned isolate running `FlutterPPGService` entirely off the UI isolate). `CameraPpgSession`'s measurement path now routes through it; the signal-based auto-detect probe stays on the UI isolate (short-lived, not FPS-sensitive). On-device confirmed (Samsung A70): 224/224 frames processed with 0 errors validated variant (a); a heavy-animation proof showed SQI held good (35/36) under sustained UI-isolate load while average FPS dropped (30.0 → 20.22) — a mitigation, not immunity, since `startImageStream`'s callback still fires on the UI isolate. Public streams unchanged. Specs: `.ai-factory/notes/13-isolate-frame-offload.md`. [1h 17m 4s]

## Phase 7 — Example app (developer playground)

> The single `example/` app — a developer-facing dogfood tool, not an end-user UX. A two-tab shell: the existing raw panels, plus the kit-API tab.

- [x] **Tabbed example: Raw + Kit-API tabs** — wrap the example in a `TabBar`/`TabBarView`. **Tab 1 (Raw)** = the existing Phase-2 panels (auto-detect + stream inspector) wired straight to `flutter_ppg`/`camera`, kept as-is — the signal/FPS ground-truth instrument. **Tab 2 (Kit API)** = dogfoods the public barrel only (`CameraPpgSession` via the `CameraPpgService` singleton + Riverpod providers): start/stop, `rrStream`/`qualityStream`/`stateStream`, prominent `MeasurementState`, display-only BPM, camera override, and a small `[debug]` panel to live-tune the gate/policy defaults. The only place the barrel is exercised before mind_mobile. Spec: `.ai-factory/notes/14-example-measurement-screen.md`. [36m 15s]
- [x] **Camera + runtime permissions** — request camera permission, handle denied / permanently-denied with a settings deep-link; iOS `NSCameraUsageDescription`, Android runtime flow. Spec: `.ai-factory/notes/15-camera-runtime-permissions.md`. [8m 48s]

---STOP---
(calibration #1)

> **CALIBRATION HANDOFF — finger needed.** Phases 3–7 are pure Dart + on-device verify and run straight through to here without calibration. Now the example's **Kit-API tab** exists, so the algorithm defaults borrowed from neiry's chest PPG must be tuned for camera PPG **against a reference pulse** (oximeter / chest strap / manual count): the RR-gate thresholds (note 12 — 300 ms floor, 40% consistency, cold-start, median window) and the session-policy windows (note 09 — warm-up, target duration, SQI floor). Report good numbers → they become the internal defaults before the API freeze (Phase 10). Resume Phases 8–10 after.

## Phase 8 — CameraPpgService singleton

- [ ] **CameraPpgService device-layer singleton** — example-app composition root: a plain-Dart service (no Flutter/Riverpod/camera imports) owning one `CameraPpgSession` behind broadcast controllers kept open across stop/start, exposed via a Riverpod provider — mirrors neiry's `NeiryService` to avoid lazy-init bugs. Spec: `.ai-factory/notes/16-camera-ppg-service-singleton.md`.

## Phase 9 — Plugin hardening

> Hardens the lifecycle paths the spike and example surface.

- [ ] **Lifecycle & teardown** — single ordered, idempotent `_release()` in `CameraPpgSession`: stop stream → close input bridge → cancel subscription → dispose service → torch off → dispose controller (the close-before-cancel order the spike proved; the naive reverse-of-start deadlocks). Release on dispose / background / hot-restart; the `WidgetsBindingObserver` lives in the example, not the kit. Spec: `.ai-factory/notes/17-lifecycle-teardown.md`.
- [ ] **Permission / unsupported-device gating** — gate denied-permission and unsupported-device paths without crashes, surfacing `CameraPpgError` values; the deny/allow-list is a data-driven JSON asset keyed by model (sourced from note 03), not model strings in Dart. Acquire nothing on refusal. Spec: `.ai-factory/notes/18-permission-unsupported-gating.md`.

## Phase 10 — Integration readiness

- [ ] **Drop-in API freeze + docs** — finalize the barrel to match `mind_mobile`'s RR-interval source contract (tagged `camera_ppg`, preferred-with-fallback alongside worn sensors); enumerate the `[debug]` extras explicitly; consumer README/docs. The `lib/Biometrics/` adapter lives in `mind_mobile`, not here. Spec: `.ai-factory/notes/19-drop-in-api-freeze.md`.

---STOP---
(calibration #2)

## Phase 11 — Torch brightness regulation (optional, native)

> **Behind the ship path + CALIBRATION — finger needed.** A comfort/safety improvement surfaced by the spike (the torch heats the fingertip over 30–60 s), not required to ship. Needs your finger: find the **minimum torch brightness that still yields a usable signal** (against a reference pulse) before exposing any control. Preview task only; spec note to be written when scheduled.

- [ ] **Torch brightness regulation (where the OS allows)** — contact PPG runs the torch at full power for 30–60 s, which heats the fingertip. The `camera` plugin's `setFlashMode` is binary on/off, so dimming needs a thin native method channel: iOS `AVCaptureDevice.setTorchModeOn(level:)`, Android 13+ `CameraManager.turnOnTorchWithStrengthLevel()`; degrade to on/off where unsupported (Android ≤12, e.g. the A70). Must first establish the minimum brightness that still yields a usable signal before exposing any control. (No spec note yet.)
