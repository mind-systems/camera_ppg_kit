# Example — Neiry-Mirror Source Shell + Source Screen

**Date:** 2026-07-03
**Source:** ROADMAP Phase 7 re-decomposition (calibration handoff #1); neiry_kit example (`router.dart` `StatefulShellRoute.indexedStack`, `device_screen.dart`, `providers/neiry_service_provider.dart`); notes 14 (tab shell), 16 (`CameraPpgService`), 01 (camera exclusivity), 19 (RR-only surface)

## Key Findings

- The example must mirror neiry's **connect-once / consume-everywhere** one-to-one: one app-level service owns the source lifecycle, a single control screen starts/stops it, and every other screen is a pure consumer that **stays mounted** across navigation.
- The current example is the **opposite**: `_TabShell` hands camera ownership to the active tab and calls `stopMeasurement()` on leaving Kit-API (`main.dart._onTabChanged`) — so measurement dies on navigation, which makes a downstream consumer (the calibration screen, note 21) impossible.
- `CameraPpgService` (note 16) is already the neiry-`NeiryService` analogue — a singleton whose broadcast controllers stay open across start/stop. **Only the shell's ownership model changes; the service does not.**
- The one place camera_ppg **cannot** mirror neiry: the camera is exclusive and the **Raw** tab opens it directly (kit-bypass). Raw is a hard exclusivity boundary — entering Raw must stop the kit source. Neiry has no analogue (BLE stays connected regardless of screen).

## Details

### Reference: neiry example structure (mirror this)

- `neiry_kit/example/lib/router.dart` — `StatefulShellRoute.indexedStack`, bottom-nav; **all branch screens stay mounted** (IndexedStack), so navigation never disposes a screen or drops its subscriptions.
- `device_screen.dart` — the **only** screen with scan/connect/**start/stop**; Streams/Classifiers/Calibration screens are `ref.watch`-only consumers.
- `providers/neiry_service_provider.dart` — `Provider<NeiryService>` with `ref.onDispose(s.dispose)`. The connection is owned by the **service**, never a screen, so it persists across navigation.

### Target shell (`example/lib/main.dart`)

Replace `_TabShell`'s `TabController` / `TabBarView` + the `_onTabChanged` release rule with an **all-mounted** shell:

- **Load-bearing property:** all screens stay mounted (IndexedStack) **and** the `CameraPpgService` singleton (`cameraPpgServiceProvider`) is the **sole** owner of the source lifecycle. Switching among Source / Kit-API / Calibration **never** stops measurement or breaks streams — the screens share the service's broadcast streams and simply stay alive.
- **Realization:** adopt `go_router`'s `StatefulShellRoute.indexedStack` to match neiry one-to-one, **or** a plain `Scaffold` + `NavigationBar` + `IndexedStack` if pulling `go_router` into the example is judged disproportionate. The property above is what matters, not the router package.
- **Branches:** Source (new), Kit-API (consumer), Calibration (note 21, consumer), Raw (existing `AutoDetectScreen`).

### Source screen (new: `example/lib/screens/source_screen.dart`)

- The **sole** Start/Stop control — mirrors neiry's `device_screen`. It issues `service.startMeasurement()` / `stopMeasurement()`; it **commands** the service, the **service owns** the source.
- Carries the camera override (`availableCameras()` / `useCamera(id)`, note 08) and the camera-permission flow (reuse `kit_api_tab.dart`'s `_checkAndRequestCameraPermission()` pattern, note 15).
- **Carries the `[debug]` live-tuning panel (kept — variant B).** The knobs (`RrAcceptance`: `minRrMs`/`consistencyThreshold`/`coldStartBeats`/`medianWindow`; `SessionPolicy`: `warmup`/`target`/`silence`/`sqiFloor`) are the kit's real settings API — the ctor-injected `RrAcceptance`/`SessionPolicy` (note 07, exported `[debug]` per note 19) — and are the seed of the future auto-calibration phase (roadmap Phase 12), so they stay on the surface, not set aside.
  - **Shared config provider (new: `example/lib/providers/session_config_provider.dart`).** Holds the *current* `RrAcceptance` + `SessionPolicy` the source runs with (defaults on first build). The Source screen's panel edits it; the Source screen passes it to `service.startMeasurement(policy:, acceptance:)`. Because a `CameraPpgSession` is constructed with an immutable config (a fresh session per `startMeasurement`, note 16), a knob change applies on the **next (re)start** — edit → Stop → Start, exactly as the old Kit-API panel did (note 14).
  - **Honesty link to calibration:** the calibration screen (note 21) reads this **same** provider to pass the actual in-force config into `recorder.start`/`recorder.save`, so the recorded JSON always describes the params that were really running — not fresh defaults.
- Shows source status (`MeasurementState`, SQI, finger-presence via the existing providers) so the operator confirms the source is live before leaving for a consumer screen.

### Kit-API screen → pure consumer (`example/lib/screens/kit_api_tab.dart`)

Strip Start/Stop (moved to the Source screen); it becomes `ref.watch`-only display of the live streams (RR + `isArtifact`, derived BPM, SQI, finger-presence, `MeasurementState`). No lifecycle, no camera, no `startMeasurement`.

### Raw exclusivity (the one neiry deviation)

Raw (`AutoDetectScreen`) uses a direct `CameraController` (kit-bypass, note 14). In the all-mounted shell, selecting the **Raw** branch must stop the kit source (`service.stopMeasurement()`) so the two never contend for the exclusive camera (note 01). Raw opens its own camera only on its explicit Start (note 14 — never on entry) and tears it down on leave, as today. So the shell keeps **one narrow** navigation hook — "selected branch == Raw → stop kit source" — replacing the old "leaving any service tab → stop."

## Guards

- Kit `lib/` untouched; recorder (note 20) untouched; `CameraPpgService` (note 16) untouched — only the shell's ownership model changes.
- **RR-only source** (note 19 pin): no HR stream; the kit emits RR + quality, HR is the consumer's derivative.
- Camera exclusivity (note 01): exactly one owner at a time — the kit source across Source/Kit-API/Calibration, or Raw's direct controller, never both.

## Verify

- Start on the Source screen → navigate to Kit-API → live RR/BPM shown, and measurement did **not** restart (same session, streams uninterrupted).
- Navigate Source ↔ Kit-API ↔ Calibration repeatedly → measurement persists, no `CameraException`, torch stays on.
- Navigate to Raw → kit source stops (torch off); Raw's own Start works; back to a kit screen → press Start on the Source screen to resume.
