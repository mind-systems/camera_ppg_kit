# Code Review (round 2): Raw motion stream from the kit

**Plan:** `.ai-factory/plans/31-raw-motion-stream-from-the-kit.md`
**Files reviewed (in full):** `lib/src/models/motion_sample.dart`, `lib/src/motion/motion_reader.dart`, `lib/src/api/camera_ppg_session.dart`, `lib/camera_ppg_kit.dart`, `docs/measurement.md`, `pubspec.yaml` / `example/pubspec.lock`, `.ai-factory/ARCHITECTURE.md`
**Risk Level:** 🟢 Low

## Resolution of review-1

The single finding from round 1 — sensor subscriptions with no `onError`, which would raise an unhandled zone error on gyroscope-less devices — is **fixed**. Both `gyroscopeEventStream(...).listen(...)` and `accelerometerEventStream(...).listen(...)` now pass an `onError` that logs via `nlog` and swallows (`motion_reader.dart:508-514`, `:530-532`). `nlog` is imported from `../util/nlog.dart`, which stays within the stated `src/motion/` purity contract (util logging is used across the pure layers). The two-argument `(Object e, StackTrace st)` handler shape is a valid stream error callback, and `nlog`'s `error:`/`stackTrace:` named params match its usage elsewhere in the session. A gyroscope-less device now degrades to held-zero gyro values with a logged error instead of an unhandled exception — matching the kit's "no exceptions escape the boundary" discipline.

## Verification of the full change

- **Decoupling (spec note 43 hard guard)** — confirmed by reading `_onSignal` in full: nothing references motion, and `motionStream` is never read back into `rrStream`/`qualityStream`/`_acceptance`/`_policy`/`_dehalving`. The reader is deliberately kept out of `_tearDownHandles` and torn down directly in `_release()`.
- **Session-scoped emission** — the reader is constructed and started only in the synchronous `lockedAndStreaming = true` block (`camera_ppg_session.dart:416-426`); no `await` is introduced, so the no-`stale()`-gap property of that block is preserved. On every early-return/exception path the reader is never constructed, so the null-guarded teardown in `_release()` handles the idle case.
- **Idempotent teardown** — `_release()` captures-and-nulls `_motionReader`/`_motionSub` before its first `await`, then `await motionSub?.cancel()` precedes `await motionReader?.dispose()`. `MotionReader.dispose()` nulls both subs before awaiting cancel and guards `_controller.close()` with `!isClosed`, so double `dispose()`/`_release()` are safe. No forwarding subscription dangles across `start()`/`stop()` cycles.
- **`dispose()` ordering** — `await _release()` runs before `await _motionController.close()`, so the `if (!_motionController.isClosed)` guard on the forwarding path can never add-after-close.
- **Types / API** — `event.timestamp` is a `DateTime` on `sensors_plus` 7.1.0, matching `MotionSample.timestamp`; `accelerometerEventStream`/`gyroscopeEventStream`/`SensorInterval.uiInterval` are the current (non-deprecated) names; `samplingPeriod:` is the correct named param.
- **Barrel discipline** — `MotionSample` is exported in the frozen-surface block; `MotionReader`/`src/motion/` stay internal; no wrapped third-party type crosses the barrel.
- **Docs** — the `motionStream` row in `docs/measurement.md` matches the model doc wording ("m/s², gravity included" / rad/s / measurement-active-only / decoupled).
- **Security / permissions** — accelerometer & gyroscope need no iOS usage-description key and no Android runtime permission; no manifest/Info.plist change is missing. No new external surface.

## Non-blocking observations (no action needed)

- **Held gyro values can go stale if the gyro stream errors mid-session** — after an error the last-held gyro values keep being attached to accel samples. For a raw passthrough with the documented "sampled-and-held, zero until first event" contract this is acceptable; in practice a gyro error means the sensor is absent and the held values are the initial zeros. Not a defect.
- **Root `pubspec.lock` not committed** — expected for a plugin (library); only the example app commits its lock, where `sensors_plus` correctly resolves as a transitive dep.

## Verdict

The implementation is faithful to spec note 43 and the plan, correctly isolated from the PPG path, and idempotent in teardown. The round-1 finding is resolved and no new issues surfaced.

REVIEW_PASS
