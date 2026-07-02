# Plan Review: Tabbed example — Raw + Kit-API tabs

## Code Review Summary

**Files Reviewed:** plan `10-tabbed-example-raw-kit-api-tabs.md` + kit API (`lib/src/api/camera_ppg_session.dart`), models (`rr_interval.dart`), processing (`session_policy.dart`, `rr_acceptance.dart`), barrel (`lib/camera_ppg_kit.dart`), example entry (`example/lib/main.dart`, `auto_detect/log.dart`), neiry prior art (`neiry_service.dart`, `neiry_service_provider.dart`, `rr_provider.dart`), notes 09/12/14/16, ROADMAP.
**Risk Level:** 🟡 Medium

The plan is well-grounded in the actual kit surface — every API name, constructor parameter, and return type it references was verified against the code, and it correctly supersedes stale details in note 16. One genuine architectural gap (camera ownership between the two tabs) and one incorrect verify assumption need resolving before implementation.

### Context Gates
- **ARCHITECTURE.md** (present): No boundary violations. The plan honours the target shape — the service and Tab-2 UI import only the public barrel, and the example-only `CameraPpgService` is explicitly kept out of the published `lib/` surface. Aligned. `WARN` none.
- **RULES.md**: Not present — `WARN` (optional file absent, non-blocking).
- **ROADMAP.md** (present): This plan implements **Phase 7 — Tabbed example: Raw + Kit-API tabs**. Milestone linkage is explicit and correct. The plan pulls the Phase-8 `CameraPpgService` (note 16) forward, which it flags in its Assumption block with the correct calibration-handoff rationale (Tab 2 cannot dogfood the barrel without it, and the `[debug]` panel is the calibration instrument the handoff needs). This is a sound, deliberately-scoped ordering deviation — `WARN`, not blocking. Note 16's own header still says "Phase 10" (pre-renumbering); the plan's "Phase 8" reference matches the current ROADMAP, so the plan is the more current artifact.

### Critical Issues

**1. Camera mutual-exclusion between Tab 1 and Tab 2 is unaddressed (architectural).**
The kit's core hardware constraint (CLAUDE.md, note 01) is that the rear camera cannot be opened concurrently. Both tabs drive that one camera + torch: Tab 1's `AutoDetectScreen` opens it directly via `flutter_ppg`/`camera`, and Tab 2's `CameraPpgService` opens it via `CameraPpgSession`. The plan's whole design deliberately keeps Tab 2's session alive across tab switches — subscriptions live in root-scope providers, and Verify line 72 explicitly requires "Start → switch tabs → return: RR still flows on the same subscription." That means the camera + torch stay **held** while Tab 2 is offstage. If the user starts a measurement in Tab 2, switches to Tab 1, and starts auto-detect, the second `CameraController.initialize()` collides with the live one → `CameraException`.
The plan needs an explicit camera-ownership handoff and must resolve the tension it creates: e.g. add a `TabController` listener that calls `CameraPpgService.stopMeasurement()` when Tab 2 loses focus (releasing the camera for Tab 1) — but that directly contradicts the "RR still flows after returning" verify goal, so the plan must pick one behavior and state it. As written, the two requirements are mutually exclusive and the collision path is silent.

**2. Verify assumption "tab-away releases camera + torch (provider onDispose)" is incorrect (line 72).**
`cameraPpgServiceProvider` is a plain (non-`autoDispose`) `Provider` mounted in the **root** `ProviderScope` (Task 3 / Task 4). Its `ref.onDispose(s.dispose)` fires only when that root scope is torn down — i.e. app shutdown — **not** on a tab switch. Switching away from Tab 2 leaves the provider (and its held camera/torch) alive. Likewise, hot-restart tears down the isolate without a graceful `onDispose` pass, so it cannot be relied on to turn the torch off. This is the flip side of Issue 1: the plan both assumes the camera is released on tab-away (this line) and assumes it survives tab-away (line 72 / the provider design) — only one can be true. Correct the verify expectation to match whichever ownership model Issue 1 settles on. If genuine release-on-leave is wanted, that requires an explicit `stopMeasurement()` on tab-blur, not `onDispose`.

### Non-Critical Issues

**3. `bpmProvider` cannot derive from the raw `rrProvider` value alone (Task 3).**
`rrProvider` is a `StreamProvider<RrInterval>` whose *latest* value is frequently an `isArtifact == true` beat (the kit emits artifact beats on the same stream — see `_onSignal` and Task 5's "do not filter rejected beats"). A "display-only `bpmProvider` computing `60000 / intervalMs` from the latest **non-artifact** `RrInterval`" therefore cannot be a simple map over `rrProvider.value` — it must **retain** the last non-artifact interval across intervening artifact ticks, or watch a separately-filtered source. Otherwise BPM either reads off artifact beats (contradicting the plan's own "non-artifact" wording) or goes stale/null whenever the newest beat is an artifact. Spell out the retained-state requirement in Task 3.

**4. `stopMeasurement()` double-teardown is redundant (Task 2).**
The task calls `await _session!.stop()` **then** `dispose()`. In the real API, `stop()` runs `_release()` and `dispose()` also runs `_release()` (idempotent) before closing the session's own controllers — so `_release()` runs twice. Since the service creates a fresh `CameraPpgSession` on every `startMeasurement`, `dispose()` alone is sufficient and correct; the extra `stop()` is harmless but pointless. Minor — simplify to a single `dispose()`.

### Positive Notes
- **Accurate API reading that corrects note 16.** Note 16 specifies `startMeasurement({CameraId? camera})` returning `Future<void>` and throwing `StateError`. The plan instead uses `startMeasurement({String? cameraId, SessionPolicy?, RrAcceptance?})` returning `Future<CameraPpgError?>` and routing `cameraId` through `session.useCamera(String id)` before `session.start()`. That matches the **actual** session signatures (`useCamera(String)`, `start()` returns a typed `CameraPpgError?` and never throws). The plan read the code, not just the stale note — good.
- **`availableCameras()` enumeration is genuinely safe.** `CameraPpgSession.availableCameras()` is verified read-only (opens no controller, never touches the torch), so the plan's transient-session enumeration for the override UI is sound and the "controllers-stay-open" invariant is preserved.
- **Debug-panel knobs match the real constructors exactly.** `SessionPolicy(warmupDuration, targetDuration, silenceWindow, sqiFloor)` and `RrAcceptance(minRrMs, consistencyThreshold, coldStartBeats, medianWindow)` are all present with those exact names — Task 6 is buildable as written.
- **Import-boundary discipline** (barrel-only in the service and Tab 2, no `CameraImage`/`PPGSignal`/`FlutterPPGService`/`CameraController` leakage) correctly enforces the note-19 API freeze, and the service-as-plain-Dart rule mirrors neiry's `NeiryService` faithfully.
- **Logging convention** (`ppgTap` before each handler, `ppgLog` for milestones) matches `example/lib/auto_detect/log.dart` and the kit CLAUDE.md; `log.dart` is plain-Dart (`dart:developer`), so the plain-Dart service can use it without importing Flutter.
