## Code Review Summary

**Plan:** `.ai-factory/plans/31-raw-motion-stream-from-the-kit.md`
**Files Reviewed:** plan (6 tasks) against `lib/src/api/camera_ppg_session.dart`, `lib/src/models/rr_interval.dart`, `lib/camera_ppg_kit.dart`, `docs/measurement.md`, `pubspec.yaml`, spec note 43, ARCHITECTURE.md, rules/base.md, ROADMAP.md (Phase 10.5)
**Risk Level:** 🟢 Low

### Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — PASS. The new `src/motion/` folder is a pure-Dart plumbing sibling of `api/models/channel/processing/util`, depending only on `src/models/` + `sensors_plus` (no `camera`/`flutter_ppg`/channel imports). This honors the "processing is pure and isolate-friendly" principle and the "adding to the public surface is a deliberate act" boundary rule — the barrel exports the model and keeps `MotionReader` internal. No wrapped third-party type crosses the barrel. The plan states the `src/motion/` purity contract inline (Task 3), which is the right way to introduce a new layer not yet named in ARCHITECTURE.md.
- **Rules (`.ai-factory/rules/base.md`)** — PASS. `flutter pub add` (no hand-edit of `pubspec.yaml`), `snake_case` filenames (`motion_sample.dart`, `motion_reader.dart`), `PascalCase` `MotionSample`/`MotionReader`, `lowerCamelCase` fields, logging kept minimal, and the new dependency (`sensors_plus`, pure-Dart) is the single deliberate addition. Aligned. (Nit below on the `/usr/local/bin/flutter` automation-path rule.)
- **Roadmap (`.ai-factory/ROADMAP.md`, Phase 10.5, line 105)** — PASS. The milestone "Raw motion stream from the kit" maps 1:1 to the plan: `sensors_plus` via `flutter pub add`, `MotionSample` model (barrel-exported), `motion_reader.dart` subscribing accel+gyro at `SensorInterval.uiInterval` → combined sample per accel tick, broadcast `motionStream` started on sensor-lock and stopped in `_release()`, full decoupling, no native code, docs-table row.
- **Governing spec (note 43)** — PASS. Every guard is carried through: raw passthrough only (no stillness index / rate cap), full decoupling from `RrAcceptance`/`SessionPolicy`/`_dehalving`/frame isolate, session-scoped emission, no native code, docs row. The units fork ("accel incl. gravity or userAccelerometer — pick one and document") is resolved: the plan commits to raw `accelerometerEventStream` (m/s², gravity included) and documents it in both the model doc and the streams row.

### Resolution of plan-review-1

The one substantive item from review-1 — the under-specified forwarding-subscription / `samples`-controller teardown — is now fully pinned, using **both** fixes review-1 recommended:

- **Task 3** now specifies a broadcast `samples` controller, a **synchronous `void start()`**, and an **idempotent `Future<void> dispose()` that closes the `samples` controller** in addition to cancelling both sensor subscriptions — so any downstream forwarding subscription completes rather than dangling.
- **Task 4** now names a dedicated `StreamSubscription<MotionSample>? _motionSub`, captures-and-nulls it alongside `_motionReader` in `_release()` (before any `await`, matching the atomic-capture discipline), and `await _motionSub?.cancel()` + `await _motionReader?.dispose()`. The reader is kept out of the shared `_tearDownHandles` ordering (correct — it is independent of the camera path).

The remaining review-1 minor notes are also resolved in the plan text: sync-start rationale is spelled out against the no-`await` `lockedAndStreaming` block; `timestamp` is pinned to `event.timestamp` with the doc-softening fallback if that field is unavailable; `dispose()` ordering (`_release()` before the `close()` block) is confirmed; the units choice is documented consistently.

### Critical Issues

None. No DB/proto/migration surface in this kit. No new security surface — accelerometer/gyroscope via `sensors_plus` need no iOS usage-description key and no Android runtime permission (only activity/step counting would). File paths are correct (`lib/src/models/motion_sample.dart`, `lib/src/motion/motion_reader.dart`, `lib/src/api/camera_ppg_session.dart`, `lib/camera_ppg_kit.dart`, `docs/measurement.md`).

### Verification against the code

- **Start point (Task 4)** — correct. `_stopwatch..reset()..start()` / `_setState(MeasurementState.warmup)` / `lockedAndStreaming = true` sit at lines 394–399, a synchronous block with no `await` and no `stale()` re-check. A synchronous `MotionReader.start()` slots in here without opening a staleness gap. On every early-return/exception path the reader is never constructed, so the inner `finally` (`_tearDownHandles` when `!lockedAndStreaming`) and the outer `_release()` never touch a half-built reader.
- **`_release()` wiring (Task 4)** — correct. Lines 473–483 capture-and-null all handles before the first `await`; adding `_motionReader`/`_motionSub` to that atomic capture matches the existing discipline, and the null-guarded cancel/dispose covers the idle case (reader never started).
- **`dispose()` ordering (Task 4)** — correct. `await _release()` (line 447) runs before the `close()` block (lines 448–453); adding `await _motionController.close();` there means the `if (!_motionController.isClosed)` guard on the forwarding path can never add-after-close.
- **Constructor controller (Task 4)** — correct. `_motionController = StreamController<MotionSample>.broadcast()` fits the initializer list at lines 56–63 where the six existing controllers are opened.
- **API surface (Task 3)** — `accelerometerEventStream` / `gyroscopeEventStream` / `SensorInterval.uiInterval` are the current `sensors_plus` names (not the deprecated `accelerometerEvents` getters), and `sensors_plus` events carry a `DateTime timestamp` field, so `event.timestamp` is available as Task 3 assumes. SDK `^3.11.0` is compatible.
- **Barrel (Task 5)** — correct. `export 'src/models/motion_sample.dart';` belongs in the frozen consumer-surface export block (lines 10–16); `motionStream` reaches consumers via the already-exported `CameraPpgSession`; `MotionReader`/`src/motion/` stay unexported, matching the boundary rule.
- **Docs (Task 6)** — correct. `docs/measurement.md` has the Streams table at lines 22–28; a `motionStream` row fits the existing style. Ensure the row's wording ("m/s², gravity included") matches the `MotionSample` model doc exactly.

### Minor Notes (non-blocking)

- **Automation flutter path.** `rules/base.md` says "Invoke Flutter as `/usr/local/bin/flutter` from automation." Task 1 writes the command as `flutter pub add sensors_plus`; the implementer running under automation should use the absolute path. Cosmetic — does not change the plan's correctness.
- **`MotionSample` field ordering / `const` ctor.** Task 2 mirrors `rr_interval.dart` (`@immutable`, `const` ctor, `required` named params) — good. Keep the seven fields `final` and the ctor `const` so the type stays a pure value type consistent with the other models.
- **`sensors_plus` version pin.** `flutter pub add` will resolve the latest compatible major. The current `sensors_plus` (6.x) keeps the `accelerometerEventStream`/`gyroscopeEventStream`/`SensorInterval` API and the event `timestamp` field, so no code change is needed; just confirm the resolved version lands cleanly against SDK `^3.11.0`.

### Positive Notes

- Decoupling is specified precisely and matches the spec's hard guard: the reader never touches `_dehalving`/`_acceptance`/`_policy`/`_frameIsolate`, is kept out of `_onSignal`, and is deliberately excluded from the shared `_tearDownHandles` camera ordering — torn down directly in `_release()` instead.
- The teardown discipline now matches the kit's "release is ordered and idempotent, no stranded handles" invariant on both sides (reader-internal `samples` close + session-level `_motionSub` cancel), so no forwarding subscription dangles across `start()`/`stop()` cycles.
- Sync-vs-async `start()` is reasoned about explicitly and pinned to `void`, protecting the no-`stale()`-gap property of the lock block.
- Commit plan is coherent and each commit is independently buildable (dep+model → reader+wiring → export+docs).
- Timestamp and units semantics are pinned with the exact monotonic-vs-wall-clock caveat already established in `rr_interval.dart`.

### Verdict

The plan is architecturally sound, faithful to spec note 43 and the Phase 10.5 roadmap line, and correct against the current `camera_ppg_session.dart` (start point, `_release()` capture, `dispose()` ordering, constructor controller, barrel block, docs table). The single substantive item from plan-review-1 (forwarding-subscription / `samples`-controller teardown) is fully resolved. No blocking issues remain.

PLAN_REVIEW_PASS
