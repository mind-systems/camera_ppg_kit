## Code Review Summary

**Plan:** `.ai-factory/plans/31-raw-motion-stream-from-the-kit.md`
**Files Reviewed:** plan (6 tasks) against `lib/src/api/camera_ppg_session.dart`, `lib/src/models/rr_interval.dart`, `lib/camera_ppg_kit.dart`, `docs/measurement.md`, `pubspec.yaml`, spec note 43, ARCHITECTURE.md, rules/base.md, ROADMAP.md
**Risk Level:** 🟢 Low

### Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — PASS. The new `src/motion/` folder is a pure-Dart plumbing layer that depends only on `src/models/` + `sensors_plus` (no `camera`/`flutter_ppg`/channel imports), consistent with the "processing is pure and isolate-friendly" principle. The barrel adds one model export and keeps the reader internal — the boundary rule ("adding to the public surface is a deliberate act") is honored, and this is explicitly sanctioned as an additive post-freeze addition (note 19). No `flutter_ppg`/`camera` type crosses the barrel. `src/motion/` is a new sibling of the documented `api/models/channel/processing/util` layers — a reasonable extension of "structured modules by technical layer," and the plan states its purity contract inline. No boundary violation.
- **Rules (`.ai-factory/rules/base.md`)** — PASS. `flutter pub add` (no hand-edit of pubspec), `snake_case` filenames, `PascalCase` type, `lowerCamelCase` fields, logging kept minimal, no dependency beyond the sanctioned set (`sensors_plus` is the deliberate new one). Aligned.
- **Roadmap (`.ai-factory/ROADMAP.md`)** — PASS. Milestone "Raw motion stream from the kit" (Phase 10.5, line 105) maps 1:1 to the plan; `Spec:` points to note 43, whose "The change"/"Guards"/"Public surface"/"Verify" sections the plan faithfully implements (decoupling, session-scoped, raw passthrough, no native code, no rate cap, docs row).
- **Governing spec (note 43)** — PASS. Every guard is carried into the plan: full decoupling from `_dehalving`/`_acceptance`/`_policy`/frame isolate, session-scoped emission, raw-only, no native code.

### Critical Issues

None. No missing migrations (no DB/proto in this kit), no security surface (accelerometer/gyroscope via `sensors_plus`/CMMotionManager need no iOS `NSMotionUsageDescription` and no Android runtime permission — only pedometer/activity would), no wrong file paths, correct API names.

### Issues / Recommendations

1. **Forwarding-subscription lifecycle is under-specified (potential dangling subscription across `start()`/`stop()` cycles).** — *Medium, should be pinned before implementation.*
   Task 4 says to "pipe its `samples` into `_motionController` via a subscription," and the stop bullet says to "dispose it (cancel its subscription + the reader)." But the plan introduces only one field, `MotionReader? _motionReader`, and does not name a field for the **session-level forwarding subscription** (`StreamSubscription<MotionSample>` from `motionReader.samples` → `_motionController`). Because `_motionController` is broadcast and stays open across cycles (closed only in `dispose()`), each `start()` creates a fresh reader + a fresh forwarding subscription; if that subscription isn't captured and cancelled in `_release()`, and if `MotionReader.dispose()` (Task 3) only "cancels both subscriptions" without **closing its `samples` broadcast controller**, the old forwarding subscription is left subscribed to a controller that will never emit or complete. In practice it's GC-reclaimed rather than a hard leak, but it violates this kit's explicit "release is ordered and idempotent, no stranded handles" invariant that the rest of `_release()`/`_tearDownHandles` upholds.
   **Fix:** pin down one of two things (a) store the forwarding subscription in a dedicated field (e.g. `StreamSubscription<MotionSample>? _motionSub`), capture-and-null it alongside `_motionReader` in `_release()`, and `await _motionSub?.cancel()`; and/or (b) have `MotionReader.dispose()` (Task 3) explicitly **close its `samples` `StreamController`** in addition to cancelling the accel/gyro subs. Recommend doing both for symmetry with the existing teardown discipline.

### Minor Notes (non-blocking)

- **`MotionReader.start()` sync vs async.** Task 4 starts the reader inside the `lockedAndStreaming = true` block (lines 389–401 of `camera_ppg_session.dart`), which today contains **no `await`s** — the whole block is synchronous, so there is no `stale()` window. Keep `MotionReader.start()` synchronous (`stream.listen(...)` is a sync subscription; return `void`, not `Future`) so the plan doesn't accidentally introduce an `await` and a new staleness gap into that block. If `start()` must be `Future`, do **not** `await` it there (fire-and-forget), or add a `stale()` re-check.
- **`MotionReader` is never constructed on any failure path.** Confirmed safe: the reader is created only in the success block, so `start()`'s inner `finally` (`_tearDownHandles` when `!lockedAndStreaming`) and the outer `_release()` (`!lockedAndStreaming && !stale()`) never touch a half-built reader — the null-guarded `_motionReader?.dispose()` in `_release()` handles the idle case. No leak on the enumerate/probe/init failure paths.
- **`dispose()` ordering is correct.** `dispose()` runs `await _release()` (which tears down the reader + forwarding sub) *before* `await _motionController.close()`, so the `if (!_motionController.isClosed)` guard on the forwarding path can never add-after-close. Just make sure the new `await _motionController.close();` is added in the same block as the other `close()` calls (lines 448–453).
- **Timestamp semantics doc.** Task 2's model doc says `timestamp` is "the accel tick's device time," while Task 3 permits `DateTime.now()` as a fallback (wall-clock, not device time). `sensors_plus` events do carry a `DateTime timestamp` field, so prefer `event.timestamp` to keep the doc accurate; if `DateTime.now()` is chosen instead, soften the model doc to say "capture time" rather than "device time" to avoid the same monotonic-vs-wall-clock trap already called out in `rr_interval.dart`.
- **`accel` units choice.** Spec note 43 offered `accelerometerEventStream` (gravity included) *or* `userAccelerometer` (gravity removed) — "pick one and document." The plan commits to raw `accelerometerEventStream` (m/s², gravity included) and documents it in both the model doc and the streams-table row. Consistent — good; just ensure Task 6's docs row matches the model doc wording exactly ("gravity included").

### Positive Notes

- Decoupling is specified precisely and matches the spec's hard guard: the reader never touches `_dehalving`/`_acceptance`/`_policy`/`_frameIsolate`, is kept out of `_onSignal`, and is deliberately excluded from the shared `_tearDownHandles` camera-ordering (it is independent) — correctly torn down in `_release()` instead.
- Start point is pinpointed correctly to the `lockedAndStreaming = true` block where `_stopwatch..reset()..start()` / `_setState(warmup)` run — the exact "sensor locks" moment the spec calls for.
- Barrel discipline is right: export the model, keep `MotionReader`/`src/motion/` internal, with a comment flagging the new public stream — matching the frozen-surface convention.
- Commit plan is coherent and each commit is independently buildable (dep+model → reader+wiring → export+docs).
- Correct API surface: `accelerometerEventStream`/`gyroscopeEventStream`/`SensorInterval.uiInterval` are the current `sensors_plus` names (not the deprecated `accelerometerEvents` getters); SDK `^3.11.0` is compatible.

### Verdict

The plan is architecturally sound and faithful to the governing spec. The single substantive item — pinning the forwarding-subscription/`samples`-controller teardown so it matches this kit's idempotent, no-stranded-handles invariant — should be resolved in the plan (or consciously by the implementer) before or during Task 3/Task 4.
