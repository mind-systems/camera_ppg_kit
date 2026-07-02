# Plan Review 2: Tabbed example — Raw + Kit-API tabs

## Code Review Summary

**Files Reviewed:** plan `10-tabbed-example-raw-kit-api-tabs.md`; kit API `lib/src/api/camera_ppg_session.dart`; processing `session_policy.dart`, `rr_acceptance.dart`; barrel `lib/camera_ppg_kit.dart`; example `main.dart`, `auto_detect/auto_detect_screen.dart`, `inspector/stream_inspector_screen.dart`, `example/pubspec.yaml`; neiry prior art `neiry_kit/example/lib/services/neiry_service.dart`, `providers/neiry_service_provider.dart`, `providers/rr_provider.dart`, `providers/stream_providers.dart`; plan-review round 1.
**Risk Level:** 🟢 Low

This is round 2. All four round-1 findings (two critical, two non-critical) are resolved in the current plan, and each resolution was re-verified against the actual code — not just taken at its word. The API names, constructor parameters, return types, teardown semantics, and dependency set the plan relies on all match the checked-in kit. Two small non-blocking refinements remain; neither invalidates the plan.

### Context Gates
- **ARCHITECTURE.md** (present): No boundary violation. The example-only `CameraPpgService` + providers are plain Dart consuming only the public barrel; nothing is added to the published `lib/` surface. The service is explicitly barred from importing `flutter`, `camera`, `flutter_ppg` (Task 2). Aligned — no WARN.
- **RULES.md**: Not present — `WARN` (optional file absent, non-blocking).
- **ROADMAP.md** (present): Implements the "Tabbed example: Raw + Kit-API tabs" milestone. The plan pulls the `CameraPpgService`/provider layer (note 16, formally Phase 8) forward with an explicit, well-argued Assumption block (Tab 2 cannot dogfood the barrel without it; the later phase hardens rather than introduces it). Deliberate, scoped ordering deviation — `WARN`, not blocking.

### Round-1 Issue Resolution (all confirmed)
1. **Camera mutual-exclusion (was Critical) — RESOLVED.** The plan adds an explicit "Camera-ownership model" block and Task 4's `TabController` listener that calls `stopMeasurement()` when the selection leaves Tab 2, tearing down camera + torch. It picks release-on-leave and drops the contradictory "RR keeps flowing offstage" goal. Verified against `start()`: a second `CameraController.initialize()` while another is live would throw `CameraException`, so the handoff is genuinely required, and `stopMeasurement()` → `_session.dispose()` → `_release()` → `_tearDownHandles` does turn the torch off (`setFlashMode(FlashMode.off)`, line 499) and dispose the controller.
2. **Incorrect "onDispose releases on tab-away" verify assumption (was Critical) — RESOLVED.** The Verify section now states measurement does not continue offstage (intended release-on-leave) and correctly scopes `cameraPpgServiceProvider.onDispose` to root-scope/app-shutdown teardown only, with background/hot-restart deferred to Phase 9.
3. **`bpmProvider` retained state (was Non-Critical) — RESOLVED.** Task 3 now specifies a `Notifier`/`NotifierProvider<int?>` that ignores `isArtifact == true` beats and holds `60000 ~/ intervalMs` from the last accepted beat across artifact ticks. Confirmed necessary: `_onSignal` (line 575) emits both accepted and artifact beats on the same `rrStream`, so the latest value is frequently an artifact.
4. **`stopMeasurement()` double teardown (was Non-Critical) — RESOLVED.** Task 2 now calls `dispose()` only and explicitly says not to also call `stop()`. Confirmed correct: `stop()` and `dispose()` both run the idempotent `_release()`, so a fresh-per-start session needs only `dispose()`.

### API accuracy re-check (all exact)
- `SessionPolicy({warmupDuration, targetDuration, silenceWindow, sqiFloor})` — matches Task 6 knobs exactly.
- `RrAcceptance({minRrMs, consistencyThreshold, coldStartBeats, medianWindow})` — matches Task 6 knobs exactly.
- `CameraPpgSession({policy, acceptance})`, `useCamera(String)` (throws `StateError` only while running — Task 2 sequences it before `start()`, so safe), `start()` returns `Future<CameraPpgError?>` and never throws, `availableCameras()` is read-only (opens no controller/torch), `stop()`/`dispose()` — all as the plan describes.
- Barrel exports every model the plan surfaces (`RrInterval`, `SignalQuality`, `MeasurementState`, `FingerPresence`, `CameraPpgError`, `CameraPpgCameraInfo`) — Tab 2's barrel-only import is buildable.
- `example/pubspec.yaml` already carries `camera ^0.12.0+1` and `flutter_ppg ^0.2.4`; `flutter_riverpod` is genuinely the only new dependency (Task 1 correct).
- Neiry prior-art paths cited (`services/neiry_service.dart`, `providers/neiry_service_provider.dart`, `rr_provider.dart`, `stream_providers.dart`) all exist under `neiry_kit/example/lib/` — the mirroring references are accurate.

### Non-Critical Refinements (non-blocking)
1. **`bpmProvider` reset trigger is under-specified (Task 3).** The plan says "reset to `null` on a new measurement," but a `Notifier` subscribed to `rrStream` alone has no clean signal for *when* a new measurement begins — `rrStream` is quiet during warm-up and carries no start marker, so the last BPM from the prior measurement would otherwise persist across a stop → start. Suggest the implementer also observe `stateProvider` (reset when state enters `warmup`, or clears on `idle`) or have the service expose a measurement generation. Display-only, so imperfect behavior is cosmetic — worth a one-line spec, not a blocker.
2. **Reverse-direction collision rests on an implicit navigation assumption.** The handoff only releases Tab 2 on leave; it does not release Tab 1. This is safe *because* Tab 1's `AutoDetectScreen.initState` only enumerates (read-only `availableCameras()`, no controller opened) and the sustained-measurement `StreamInspectorScreen` — which does hold the camera + torch for its lifetime (`MeasurementRunner`, released in `dispose`) — is a full-screen `Navigator.push` on the root navigator, so the `TabBar` is unreachable while it is open. The one-directional handoff is therefore sufficient, and any residual race (pop inspector → very fast tab-switch → Start) surfaces as Tab 2's typed `CameraPpgError` + retry, not a crash. Worth stating this assumption in Task 4 so a future refactor that puts the inspector inside the tab (or opens a camera in Tab 1's `initState`) doesn't silently reintroduce the collision.

### Positive Notes
- **Idempotent-by-design handoff.** A `TabController` listener fires repeatedly during a swipe; `stopMeasurement()` is a no-op when `_session == null` and `_release()` is idempotent, so repeated firings are harmless — the plan's ownership model is robust to the listener's real firing behavior without extra guarding.
- **Controllers-stay-open invariant correctly preserved.** `stopMeasurement()` leaves the service's own broadcast controllers open, so returning to Tab 2 keeps the same provider subscriptions — no `Bad state: Stream has already been listened to`. This matches `CameraPpgSession`'s own "streams stay open across start/stop, only dispose closes them" contract.
- **Import-boundary discipline** (barrel-only in service and Tab 2, no `CameraImage`/`PPGSignal`/`FlutterPPGService`/`CameraController` leakage) faithfully mirrors neiry's plain-Dart `NeiryService` and enforces the note-19 API freeze.
- **Debug panel is buildable as written** — every knob maps to a real constructor parameter with the exact name.

The plan is solid and implementable. The two refinements above are advisory and do not require another review round.

PLAN_REVIEW_PASS
