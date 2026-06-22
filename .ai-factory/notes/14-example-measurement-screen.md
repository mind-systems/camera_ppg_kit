# Example — Tabbed Developer Playground

**Date:** 2026-06-22
**Source:** ROADMAP Phase 7; existing `example/lib/` Phase-2 panels (`auto_detect/`, `inspector/`); neiry `example/` (providers/rr_provider.dart, neiry_service_provider.dart); notes 07 (session + streams), 08 (camera override), 09 (session policy), 16 (CameraPpgService singleton)

## Key Findings

- **The example is a `TabBar` / `TabBarView` shell with two tabs**, not a single kitchen-sink screen. The split mirrors the two ways the kit can be touched, kept visibly separate so a developer always knows which layer they're looking at.
- **Tab 1 — Raw (direct `flutter_ppg`).** This is exactly what Phase 2 already built (`example/lib/auto_detect/` + `inspector/`), kept as-is: the auto-detect round-trip and the raw stream inspector wired **straight to `flutter_ppg` / `camera`**, bypassing the kit. It is the signal-existence / FPS instrument — "does this phone produce a usable optical PPG, and what frame rate does the path sustain?" — and it answers that without depending on any kit code. Leave it working; do not rewrite it onto the kit API.
- **Tab 2 — Kit API (dogfood).** Consumes the kit's **public barrel only** (`CameraPpgSession` via the `CameraPpgService` singleton + Riverpod providers, note 16). This is the *only* place the published surface is exercised before `mind_mobile` depends on it, so it doubles as the integration smoke-test. Kept deliberately simple: start/stop, the three streams, prominent `MeasurementState`, and the few knobs that matter — not "every knob".
- **Why Tab 2 needs live tuning.** The RR-gate thresholds (note 12) and session-policy defaults (note 09) come from neiry's chest PPG; we don't yet know the right values for camera PPG. Tab 2 carries a small `[debug]` panel to tune them live (via the optional `RrAcceptanceConfig` on the session, note 07) — good values become the new internal defaults. This is the one real reason Tab 2 has settings at all.
- BPM is **display-only** (`60000 / intervalMs` from the latest non-artifact `RrInterval`); the kit never emits BPM/HRV (note 07). No aggregate result summary — that is the host's job, not the kit's.

## Details

### Shell

`example/lib/main.dart` hosts a `TabBar` + `TabBarView` (or a `NavigationBar`) with two tabs: **Raw** and **Kit API**. Keep it plain — no go_router needed unless Tab 2 grows sub-routes.

### Tab 1 — Raw (keep existing)

The current `AutoDetectScreen` + `StreamInspectorScreen` move under this tab unchanged. They keep talking directly to `flutter_ppg`/`camera` through the existing `coverage_detector.dart` / `measurement_runner.dart`. No conversion to the kit API — its value is being the un-abstracted ground truth. (Guard: this tab is allowed to import `flutter_ppg`/`camera`; Tab 2 is not.)

### Tab 2 — Kit API (new, simple)

A `ConsumerWidget` reading one running `CameraPpgService` (note 16) via Riverpod `StreamProvider`s — no `StreamBuilder`, no per-widget `.listen()` (neiry's stream-ownership lesson: subscriptions live in providers so a rebuild never re-subscribes).

- **Start / Stop** — drives `CameraPpgService.startMeasurement()/stopMeasurement()`. Stop returns to idle, not a results screen.
- **`MeasurementState`** (prominent) — `warmup` → "hold still…", `measuring` → live, `poorSignal` → guidance, `done` → "complete". Proves the kit-owned lifecycle (note 09) works with zero host logic.
- **RR** — latest `intervalMs` + a short rolling list; **`isArtifact` shown, not filtered** (a developer wants to see rejected beats).
- **Derived BPM** (large, display-only) from the latest non-artifact interval.
- **SQI chip** + **finger-presence** indicator.
- **Camera override** — show which sensor auto-detect locked; list rear sensors and let `useCamera(id)` pin one before start (note 08).
- **`[debug]` tuning panel** — warm-up / target duration (note 09) and the RR-gate params via `RrAcceptanceConfig` (note 12). The only settings here; mark them `[debug]` so they are never mistaken for host config.

Optional: a live `CameraPreview` via a service-exposed preview builder (never a `CameraController` across the barrel) and the `[debug]` red-channel waveform (`debugSignalStream`, `List<double>`, note 07) — add only if cheap; Tab 1 already covers raw-signal inspection.

### `example/lib/` additions

- `providers/camera_ppg_service_provider.dart` — `Provider<CameraPpgService>` with `ref.onDispose(s.dispose)` (note 16).
- `providers/stream_providers.dart` — `rrProvider` / `qualityProvider` / `stateProvider` off the service streams, plus a display-only `bpmProvider`.
- `screens/kit_api_tab.dart` — the `ConsumerWidget` above.
- `flutter pub add flutter_riverpod` in `example/`. Camera permission is **note 15** — reference, do not duplicate.

### Verify

- **Tab 1** still runs the Phase-2 flow unchanged (auto-detect locks the covered sensor; inspector shows raw `PPGSignal`).
- **Tab 2**: finger on lens+flash → Start → auto-detect locks → `warmup` ("hold still…") → `measuring` with plausible BPM → `done` at the default duration, all with no app-side logic. No finger → typed `CameraPpgError` + retry, no torch-strobe loop. Lift finger → finger-presence flips, SQI drops, `isArtifact` beats appear, `poorSignal`, then recovery. Hot-restart / tab-away releases camera + torch (provider `onDispose`).

### Guards

- Tab 2 imports **only** the kit barrel — no `CameraImage` / `PPGSignal` / `FlutterPPGService` type. Tab 1 keeps its direct `flutter_ppg`/`camera` access.
- No `StreamBuilder` / per-widget `.listen()` in Tab 2 — subscriptions live in providers.
- BPM/HRV derived in the example only, never pushed into the kit.
- The warm-up→done lifecycle is the **kit's** (note 09); Tab 2 only renders `stateStream`, never reimplements it.
- Keep it simple — Tab 2 is dogfood + the gate/policy tuning the spike still needs, not an exhaustive knob board. No guided wellness UX, no aggregate result summary.
