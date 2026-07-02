# Plan Review: Isolate offload for the frame path (defensive)

**Plan:** `.ai-factory/plans/09-isolate-offload-for-the-frame-path-defensive.md`
**Spec:** `.ai-factory/notes/13-isolate-frame-offload.md`
**Files reviewed:** plan + spec note + `lib/src/api/camera_ppg_session.dart` + `flutter_ppg` 0.2.4 source (`flutter_ppg_service.dart`, `signal_processor.dart`, `ppg_signal.dart`) + `camera` 0.12.0+1 `camera_image.dart` + Dart SDK `dart:isolate` + ARCHITECTURE.md / ROADMAP.md / rules.
**Risk Level:** 🟡 Medium

The plan is well-researched and the overall shape (variant (a): whole `FlutterPPGService` in one long-lived isolate, `TransferableTypedData` per frame, empirical gate first) is sound and matches the source. The reconnaissance is accurate on the important points: `_onSignal` reads exactly 5 `PPGSignal` fields (verified: `rrIntervals`, `snr`, `rawIntensity`, `filteredIntensity`, `timestamp`); `processImageStream` is a pure `async*` generator with no platform-channel/`WidgetsBinding` calls in the loop; `CameraImage.fromPlatformData(Map)` is a real public (deprecated) constructor; the close-before-cancel teardown invariant is correctly identified. However, three issues below need to be fixed before implementation, one of them a latent **silent-failure on Android**.

## Context Gates

- **Architecture (WARN → resolved):** ARCHITECTURE.md rule 4 ("`src/processing/` imports `src/models/` only; no `camera`/`flutter_ppg`") is contradicted by placing a `camera`+`flutter_ppg`-importing isolate host in `processing/`. The plan's "Architecture note" reconciliation (split pure value types into `frame_message.dart`; confine `camera`/`flutter_ppg` imports to the single boundary file `frame_isolate.dart`) is a reasonable, explicitly-documented exception. **Consideration:** `frame_isolate.dart` imports exactly what `src/api/` is already allowed to import (`camera` + `flutter_ppg`); an equally clean option would be to host it under `src/api/` and keep `processing/` literally pure. Either is acceptable — just make the choice deliberate and note it in ARCHITECTURE.md so the next reader isn't surprised by a `flutter_ppg` import under `processing/`.
- **Rules (PASS):** `base.md` conventions (snake_case files, `nlog` logging, no `mind_mobile`/logger-facade dependency, no hand-editing `pubspec.yaml`, no new proto) are all respected — the plan adds no new dependency and routes logs through `nlog`.
- **Roadmap (PASS):** Directly implements ROADMAP Phase 8 "Isolate offload for the frame path (defensive)" and cites spec note 13. Linkage is explicit.

## Critical Issues

### 1. (High) yuv420 reconstruction will drop the V plane index — silent no-signal on Android
`SignalProcessor._extractRedFromYUV420` reads **`image.planes[0]` (Y) and `image.planes[2]` (V)** — it indexes position **2** directly (confirmed in `signal_processor.dart`). Tasks 2/3 say to transfer "only the planes `extractRedChannel` needs … yuv420 → planes 0 & 2" and then "rebuild a `CameraImage` … with a `planes` list."

If `cameraImageFromFrameMessage` builds a **2-element** planes list `[Y, V]`, then `planes[2]` is out of range → `RangeError`. That error is swallowed by `processImageStream`'s per-frame `try { intensity = extractRedChannel(image); } catch (e) { continue; }` (verified at `flutter_ppg_service.dart:165-170`), so **every Android frame is skipped, no `PPGSignal` is ever emitted, and no error surfaces** — the measurement silently produces nothing. iOS (bgra8888, single plane 0) is unaffected, which makes this easy to miss in testing on an iPhone.

The reconstruction must **preserve original plane indices**: build a 3-element list where V sits at index 2 (index 1 can be a placeholder/empty U plane, since `extractRedChannel` never reads index 1). Note `Plane._fromPlatformData` requires `bytesPerRow as int` (non-null), so the placeholder plane still needs a `bytesPerRow` value and a (possibly empty) `bytes`.

The plan hides this behind "shaped exactly as Task 1 proved," but Task 1 is a throwaway harness and this constraint deserves to be pinned explicitly in Task 3 so the implementer doesn't build the intuitive-but-broken 2-element list. Add it to the Task 7 synthetic-frame test explicitly (assert `rebuilt.planes.length == 3` and `rebuilt.planes[2]` carries the V bytes).

### 2. (Medium) `TransferableTypedData` lives in `dart:isolate`, not `dart:typed_data`
The plan states twice that `frame_message.dart` is "`dart:typed_data`/`dart:core` only" (Architecture note) and "Pure Dart, `dart:typed_data` only" (Task 2), while requiring `FrameMessage` to hold `List<TransferableTypedData>`. Verified against the Dart SDK: **`TransferableTypedData` is declared in `dart:isolate`** (`.../dart-sdk/lib/isolate/isolate.dart`), not `dart:typed_data`. So `frame_message.dart` **must import `dart:isolate`** — the stated "`dart:typed_data` only" constraint is impossible as written.

This does not harm the goals: `dart:isolate` is pure Dart (no Flutter/`camera`), so the file stays hardware-free, isolate-runnable, and unit-testable. But the import-constraint text is a factual error that will confuse the implementer. Fix the plan to read "`dart:typed_data` + `dart:isolate`, no `camera`/`flutter_ppg`/Flutter imports."

### 3. (Medium) Task 8's FPS / `isFPSStable` proof metric is not carried across the port
Task 8 says to "confirm sustained FPS and SQI hold at the note-02/note-03 baseline (~24 FPS `isFPSStable`, SQI good)." But `SignalMessage` is deliberately frozen to the **exact 5 fields `_onSignal` consumes** — which do **not** include `frameRate` or `isFPSStable` (both are `PPGSignal` fields the session never reads). So the isolate-backed session exposes **no way to observe `isFPSStable`/`frameRate`**: SQI is derivable (`qualityStream`), but the FPS figure Task 8 pins its "proof" on is unreachable.

Reconcile one of these ways and state it in the plan:
- add `frameRate`/`isFPSStable` to `SignalMessage` **only for the temporary Task 8 harness** (and note it must be reverted, since it widens the frozen boundary); or
- measure frame cadence on the UI isolate by counting `startImageStream` callbacks per second — but be explicit that this measures *camera→UI-isolate delivery rate*, which is a **different quantity** than `flutter_ppg`'s internal `isFPSStable` stabilization flag, and adjust the baseline wording accordingly.

Leaving Task 8 as-is makes its acceptance metric non-measurable through the shipping surface.

## Minor Issues / Notes

- **(Low) `extractRedChannel` is not part of the `flutter_ppg` public API.** The barrel (`flutter_ppg.dart`) exports `flutter_ppg_service`, `ppg_signal`, `ppg_config`, `frame_rate_detector`, `rr_interval_analyzer`, `filter_result` — **not** `signal_processor.dart`. Task 7's parenthetical "assert that `extractRedChannel` … yields the expected red-channel mean" is therefore not callable from the test via the public package. The plan already offers the fallback ("or an equivalent mean over the rebuilt bytes") — keep only that path and drop the `extractRedChannel` option to avoid a dead end. Also note the yuv420 mean formula the test must match is `Mean(Y) + 1.402*(Mean(V) - 128)` over **all** plane bytes including any row padding.

- **(Low) `CameraImage.fromPlatformData` is `@Deprecated`.** Under `flutter_lints` this raises a `deprecated_member_use` analyzer warning; an `// ignore: deprecated_member_use` on the reconstruction line will be needed to keep `flutter analyze` clean. Also: its format-group resolution (`_asImageFormatGroup`) reads `defaultTargetPlatform` and only maps yuv420/bgra8888/jpeg/nv21 — passing the correct integer `format.raw` (Android yuv420 = 35; iOS bgra8888 = 1111970369) is essential, and `defaultTargetPlatform` does resolve correctly inside a spawned isolate (via `Platform.operatingSystem`), so this works but should be called out as a dependency.

- **(Low, accuracy) "zero-copy" overstated.** `TransferableTypedData.fromList([...])` generally copies the bytes into an internal buffer at *construction*; the zero-copy win is on *transfer/materialize* across the port (no re-serialization, no second copy on receive). Still far cheaper than a map/JSON round-trip, but the "no full byte copy" phrasing in the spec and Task 3 is optimistic — don't rely on it for a hard per-frame budget claim.

- **(Context, non-blocking) The `startImageStream` callback still runs on the root/UI isolate** even after this change (spec note 13 line 10 confirms). The offload removes *PPG processing* CPU from the UI isolate; it does **not** move frame *delivery* off it. So a pathologically heavy UI-isolate animation can still starve frame delivery regardless of the isolate. This is the correct and intended mitigation (removing PPG's contribution frees headroom), but Task 8's measured delta is only meaningful if the pre-isolate collapse was driven by PPG processing *competing with* the animation on the UI event loop. Make the Task 8 harness stress exactly that, and frame the result honestly (mitigation, not immunity).

## Positive Notes

- Empirical-gate-first structure (Task 1 blocks Phase 2, verdict recorded in note 13 before coding) is exactly right for the "confirm isolate-safety empirically, don't ship on the source read" mandate.
- The teardown ordering is faithfully carried across the boundary: close-before-cancel is preserved both in the session (Task 6) and **inside** the isolate (Task 4), and isolate teardown is wired into `stop()`/`dispose()`/every `start()` abandon path — correctly preventing a leaked isolate from keeping the torch warm (spec Guards).
- The `_generation`/`stale()` abandon discipline is explicitly preserved across the new async `Isolate.spawn` await (Task 5) — a subtle correctness point the plan did not overlook.
- Errors-as-data across the port (Task 2/4: `SignalMessage` error variant, never a thrown exception) correctly mirrors the kit's "no exceptions across the boundary" rule.
- Auto-detect probe path (`_probeCameraCoverage`/`_lockCoveredCamera`) is correctly scoped **out** — it's short-lived, not the FPS-sensitive sustained path, and refactoring `_onSignal` doesn't touch it (the probe uses its own inline listener).

## Verdict

Fix findings 1–3 (especially the yuv420 plane-index reconstruction in finding 1, which will silently break Android if implemented as literally worded) and address the `dart:isolate` import correction. The Low notes can be folded into the relevant tasks. Once findings 1–3 are pinned into the task text, the plan is ready to implement.
