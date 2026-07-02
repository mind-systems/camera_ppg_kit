# Plan Review 2: Isolate offload for the frame path (defensive)

**Plan:** `.ai-factory/plans/09-isolate-offload-for-the-frame-path-defensive.md`
**Spec:** `.ai-factory/notes/13-isolate-frame-offload.md`
**Files reviewed:** plan + spec note 13 + `lib/src/api/camera_ppg_session.dart` + `flutter_ppg` 0.2.4 source (`flutter_ppg.dart` barrel, `flutter_ppg_service.dart`, `signal_processor.dart`) + `camera` 0.12.0+1 `camera_image.dart` + `.ai-factory/ARCHITECTURE.md` / `ROADMAP.md` + review-1.
**Risk Level:** 🟢 Low

## Summary

This is the round-2 revision of the plan, and it has **incorporated all three critical findings and the Low notes from review-1**, each pinned into the exact task where an implementer will act on it. I re-verified every load-bearing source claim against the installed packages; they all hold. The plan is ready to implement. The items below are clarity refinements, none blocking.

### Verification of review-1 fixes (all confirmed against source)

- **Finding 1 (yuv420 plane-index silent failure) — fixed and source-confirmed.** `signal_processor.dart:42,48` reads `image.planes[0]` (Y) and **`image.planes[2]`** (V) directly. Reconnaissance line 16 + Task 3 + Task 7 now mandate a **3-element** planes list with V at index 2 and a placeholder at index 1. Confirmed the placeholder constraints are real: `Plane._fromPlatformData` (`camera_image.dart:26-30`) casts `data['bytes'] as Uint8List` (**non-null**) and `data['bytesPerRow'] as int` (**non-null**) — so the index-1 placeholder genuinely needs a non-null `bytesPerRow` and a (possibly empty) `bytes`, exactly as the plan states. Task 7 asserts `planes.length == 3` and `planes[2]` carries V. Correct.
- **Finding 2 (`TransferableTypedData` is in `dart:isolate`) — fixed.** Plan now consistently states `frame_message.dart` imports `dart:typed_data` + `dart:isolate` (Architecture note line 23, Task 2 line 38). Correct — `TransferableTypedData` is declared in `dart:isolate`, which is pure Dart, so the file stays isolate-safe and testable.
- **Finding 3 (FPS proof metric not carried across the frozen port) — fixed.** Task 8 now spells out the reconciliation: temporarily widen `SignalMessage` with `frameRate`/`isFPSStable` for the on-device proof and **revert before commit** (stated in note 13), with the callback-counting alternative and its "different quantity" caveat spelled out. Good.
- **Low notes folded in:** `extractRedChannel` is confirmed **not** exported by the `flutter_ppg.dart` barrel (barrel exports only service, ppg_signal, ppg_config, frame_rate_detector, rr_interval_analyzer, filter_result), so Task 7 correctly replicates the formula inline instead of calling it. The `// ignore: deprecated_member_use` for `CameraImage.fromPlatformData` (confirmed `@Deprecated` at `camera_image.dart:134`) is now called out. The "zero-copy" overstatement is corrected to a transfer/materialize win (reconnaissance line 17, Task 3). All accurate.

### Additional source confirmations (new this round)

- **Format-group resolution / raw codes.** `_asImageFormatGroup` (`camera_image.dart:80`) reads `defaultTargetPlatform`, mapping Android `case 35` → yuv420 and iOS `case 1111970369` → bgra8888 — matching the plan's hardcoded codes. The live `CameraImage.format.raw` is populated (`ImageFormat._fromPlatformInterface` sets `raw = format.raw`), so the producer can forward `image.format.raw` verbatim rather than relying on the constants; the plan's Task 3 wording ("carries `format.raw`") already prefers this. Non-issue.
- **yuv420 formula for the Task 7 reference.** Confirmed `Mean(Y) + 1.402 * (Mean(V) - 128)` over **all** plane bytes (`_calculateMean` runs over the full byte list, padding included), and bgra8888 = mean of every 4th byte from offset 2 (`for (int i = 2; i < length; i += 4)`). Task 7's inline reference matches exactly.
- **The swallowed-error path is real.** `flutter_ppg_service.dart` wraps `extractRedChannel` in `try { … } catch (e) { continue; }`, so a `planes[2]` `RangeError` is silently skipped — validating why Finding 1 is a *silent* Android failure and why the Task 7 length assertion earns its place.

## Context Gates

- **Architecture (WARN → deliberately reconciled):** ARCHITECTURE.md states the `processing/` purity rule in **three** places — the Dependency Rule (line 43), invariant #4 "Processing is pure and isolate-friendly" (line 63), and the ❌ anti-pattern "Putting `camera`/channel calls inside `src/processing/`" (line 115). Task 4 currently says to add a one-line exception note to the **Dependency Rules** section only. To keep ARCHITECTURE.md internally consistent, the exception for `frame_isolate.dart` should also be reflected at invariant #4 and the ❌ bullet (or those should reference the noted exception), so the doc does not read as self-contradicting. See Note A. (The underlying reconciliation — pure value types in `frame_message.dart`, camera/flutter_ppg imports confined to the single boundary host `frame_isolate.dart` — remains sound; `frame_isolate.dart` imports only what `src/api/` is already permitted.)
- **Rules (PASS):** No new dependency, no hand-edited `pubspec.yaml`, `nlog` for kit logs / `ppgLog`/`ppgTap` for the example, no proto. All respected.
- **Roadmap (PASS):** Directly implements ROADMAP Phase 8 "Isolate offload for the frame path (defensive)" (roadmap line 39) and cites spec note 13. Linkage explicit; the "defensive / not blocking" framing matches note 13 line 8.

## Notes (non-blocking)

### A. (Low) ARCHITECTURE.md exception should cover all three statements of the purity rule
As above — Task 4 should annotate invariant #4 (line 63) and the ❌ anti-pattern (line 115) in addition to the Dependency Rule, so the recorded exception is consistent across the doc. One extra sentence.

### B. (Low, clarity) Task 5/6 gloss over the session field restructuring
Under the new design the **measurement** path stops populating the instance fields `_imageStreamCtrl` / `_service` / `_sub` (the UI-side `StreamController<CameraImage>` bridge moves *inside* the isolate) and instead holds a `_frameIsolate` + a `SignalMessage` subscription. But `_tearDownHandles(controller, imageStreamCtrl, service, sub)` is **shared with `_probeCameraCoverage`**, which legitimately keeps using `FlutterPPGService` on the UI isolate for the coverage round-trip. So the isolate teardown must be added as **optional new params (or a separate path)** that the probe passes as null — not by repurposing the existing probe handle set. Task 6's "integrate its teardown into `_tearDownHandles`" is workable but reads as if the isolate joins the same handle bundle the probe uses; make explicit that (a) the measurement path's `_imageStreamCtrl`/`_service`/`_sub` become probe-scoped only, and (b) the probe path is untouched and never receives an isolate handle. This prevents an implementer from accidentally wiring an isolate into the probe or double-tearing-down.

### C. (Low, watch-item for Task 1/8) FPS is now sampled at isolate-receive time
`FrameRateDetector.recordFrameMicros` runs **inside** the isolate, so cadence is measured when a `FrameMessage` arrives over the port, not when the camera delivered the frame to the UI isolate. Port scheduling is normally prompt (per-event microtask), so this should track the true cadence closely — but any batching/jitter on the port could shift `isFPSStable` and, because peak detection only runs when FPS is stable, subtly change output timing. This is exactly what the Task 1 empirical gate and Task 8 on-device FPS/SQI proof exist to catch, so it is already covered — worth an explicit line in note 13's Verify section so the tester watches for a cadence divergence rather than assuming parity.

## Positive Notes

- Empirical-gate-first (Task 1 blocks Phase 2, verdict written to note 13 before coding) matches the "confirm isolate-safety empirically, don't ship on the source read" mandate exactly.
- The close-before-cancel teardown invariant is carried faithfully across the boundary — mirrored **inside** the isolate (Task 4) and in the session (Task 6) — and isolate teardown is wired into `stop()`/`dispose()`/every `start()` abandon path so a leaked isolate can't keep the torch warm (spec Guards).
- `_generation`/`stale()` abandon discipline is explicitly preserved across the new async `Isolate.spawn` await (Task 5) — the one subtle correctness hazard of making the wiring async, and the plan names it.
- Errors-as-data across the port (`SignalMessage` error variant, never a thrown exception) correctly mirrors the kit's no-exceptions-across-the-boundary rule.
- The "mitigation, not immunity" framing (Task 8) is honest: `startImageStream` still fires on the root/UI isolate, so delivery isn't moved off it — only PPG *processing* CPU is. This is stated rather than oversold.

## Verdict

All review-1 findings are resolved and every load-bearing source claim re-verified against `flutter_ppg` 0.2.4 and `camera` 0.12.0+1. The three notes above are clarity/consistency refinements that can be folded into Tasks 4–6 during implementation; none blocks starting.

PLAN_REVIEW_PASS
