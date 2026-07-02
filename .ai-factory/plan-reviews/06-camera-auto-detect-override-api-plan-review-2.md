# Plan Review 2: Camera auto-detect + override API

**Plan:** `.ai-factory/plans/06-camera-auto-detect-override-api.md`
**Files Reviewed:** plan + `lib/src/api/camera_ppg_session.dart`, `lib/camera_ppg_kit.dart`, `lib/src/models/camera_ppg_error.dart`, `lib/src/models/finger_presence.dart`, note 08, ARCHITECTURE.md, rules/base.md, plan-review-1, `camera_platform_interface` 2.13.0 `CameraDescription`, example app
**Risk Level:** 🟢 Low

## Summary

This is the revised plan following plan-review-1, which raised two blocking gaps. Both are now closed in-plan and closed correctly:

1. **`flashAvailable` data source (review-1 Critical #1) — RESOLVED.** Task 1 now pins the field to the documented constant `true` for every rear entry, with a mandated dartdoc caveat that it is an unverified rear+torch assumption and must never gate selection. Verified against the source: `CameraDescription` (camera_platform_interface 2.13.0) exposes only `name`, `lensDirection`, `sensorOrientation`, `lensType` — no flash/torch property — so a constant is the only honest choice at enumeration time without opening a controller. Task 2 correctly forbids opening a controller in `availableCameras()`. Consistent.

2. **Import under-scoping (review-1 Critical #2) — RESOLVED.** The plan now specifies the additive, `show`-scoped disambiguation: keep the unprefixed `import 'package:camera/camera.dart';` (all types resolve) and add `import 'package:camera/camera.dart' as cam show availableCameras;`, changing only the single call in `_enumerateRearCameras()` to `cam.availableCameras()`. Verified valid Dart: a prefixed import combined with `show` is legal; the two imports do not collide (unprefixed vs prefixed), and `cam.availableCameras()` unambiguously targets the plugin free function while the new public instance `availableCameras()` shadows the unqualified name only *inside* the class. The plan explicitly warns against whole-file re-prefixing (the non-compiling intermediate). Correct.

## Context Gates

- **Architecture (PASS).** Boundary discipline holds: `CameraPpgCameraInfo` is a pure `models/` value type with no `camera`/`flutter_ppg` import, constructed from a `CameraDescription` only at the API edge; `CameraDescription` never crosses the barrel; the private `_enumerateRearCameras()` keeps returning `CameraDescription` internally. The pinned-id failure returns a typed `CameraPpgError.cameraUnavailable` (never throws across the boundary), and the mid-measurement misuse uses `StateError` — both match ARCHITECTURE.md's "typed values for expected states, exceptions only for programmer errors."
- **Rules (PASS).** `.ai-factory/rules/base.md` line 26 ("reserve exceptions for genuinely exceptional/programmer errors") directly supports the `StateError`-vs-`CameraPpgError` split in Tasks 3/4. No `RULES.md` and no aif-review skill-context file present — nothing to enforce beyond base.md.
- **Roadmap (PASS).** Cleanly linked to note 08 (§ "Added to `CameraPpgSession`", "Verify", "Guards"); scope ("adds override surface + diagnostics list on top of already-shipped auto-detect, does not rewrite the round-trip") matches the current code and the milestone intent.

## Correctness confirmations against the code

- **Shadowing hazard is real and correctly diagnosed.** `_enumerateRearCameras()` (line 429) calls the top-level `availableCameras()` unqualified. Adding a public instance method of the same name would resolve that call to `this.availableCameras()` → infinite recursion. The additive-import fix removes the hazard. Confirmed.
- **`lensType.name` is valid.** `CameraDescription.lensType` exists and is a `CameraLensType` enum (`wide`/`telephoto`/`ultraWide`/`unknown`, defaulting to `unknown`); `.name` yields the `String`. Task 1's "string, not an enum, frequently `unknown`" and Task 2's `d.lensType.name` are accurate. Storing a `String` rather than re-exporting the enum keeps `camera` types off the barrel.
- **Task 4 pin branch fits the existing structure.** Inserting the branch after `_enumerateRearCameras()` + its empty/`stale()` checks and before `_lockCoveredCamera(...)`, resolving by `CameraDescription.name`, then reusing the existing controller-open/torch/bridge/stream block with the resolved `description`, all map cleanly onto lines 136–237. The pin lookup is synchronous (no new `await`), so no additional `stale()` check is needed — the controller-open block's own post-`initialize()` `stale()` checks (lines 181, 201, 224) cover the async boundary. On no match, returning `CameraPpgError.cameraUnavailable(...)` and falling through the existing `finally` (which runs `_release()` → clears `_running`, returns to `idle`) is exactly the current failure contract. `CameraPpgError.cameraUnavailable({String? message})` exists (line 68). Confirmed.
- **`useCamera` guard breadth is intentional and correct.** `_running` is set `true` at the top of `start()` (line 130) before state reaches `measuring`, so keying the `StateError` on `_running` also rejects `useCamera` during the pre-`measuring` setup window. The plan flags this as deliberate and warns against "tightening" to `_state == measuring` (which would open a setup-window race). Matches the existing guard style.

## Minor Notes (non-blocking)

- **Pin lifetime is sticky by omission — make it explicit.** Task 4 never clears `_pinnedCameraId` inside `start()`, and Task 3 adds no un-pin API (correctly out of scope). The natural, intended reading is that a pin persists across repeated `start()`/`stop()` cycles until replaced by another `useCamera(id)`. That is a reasonable design, but the plan states it only implicitly. A one-line note in Task 3/4 ("the pin is sticky — it survives stop()/start() until a subsequent useCamera replaces it; there is no un-pin") would remove any implementer guesswork. Not a defect.

- **The "Verify via the example" step is not executable without example wiring — pre-existing, out of scope.** The example app (`example/lib/`) does not import or drive `CameraPpgSession` at all — it has its own standalone auto-detect/inspector code and calls the `camera` plugin's `availableCameras()` directly. So the plan's (and note 08's) on-device Verify list — `session.availableCameras()`, `useCamera(id)` then `start()`, `useCamera` during `measuring` throwing — has no host that calls it today. This gap is inherited from milestone 05 (the session itself was never wired into the example), not introduced here, and example wiring is outside this milestone's stated scope. Flagging so the implementer/tester knows a throwaway harness (or a follow-up wiring milestone) is required to actually run the Verify section; it does not block the kit-code plan.

## Positive Notes

- Both plan-review-1 blockers were closed precisely, with the fix rationale inlined at the relevant task (`review Critical #1`, the load-bearing name-shadowing box) rather than hand-waved — easy for the implementer to follow.
- The name-shadowing hazard and its additive-import remedy are surfaced up front, avoiding a compile-time surprise.
- Boundary discipline is exactly right: pure `CameraPpgCameraInfo`, no `CameraDescription` leak, barrel export called out, private enumeration keeps returning `CameraDescription`.
- Correctly additive over milestone 05: reuses `_enumerateRearCameras()`, does not touch the round-trip, preserves the `_generation`/`stale()` re-entrancy discipline, and reuses `cameraUnavailable`/`StateError` instead of inventing new state or error types.

## Verdict

Both blocking gaps from plan-review-1 are resolved correctly, and every API the plan depends on is verified present in the code and the `camera` package. The remaining items are non-blocking clarity notes (sticky-pin lifetime) and a pre-existing, out-of-scope verification-harness gap. The plan is implementable as written.

PLAN_REVIEW_PASS
