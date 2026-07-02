## Plan Review Summary

**Plan:** `12-calibration-rr-capture-android-file-export.md`
**Files Reviewed:** plan + spec note 20 + 6 targeted codebase files (`CameraPpgService`, `RrInterval`, `SignalQuality`, `MeasurementState`, `RrAcceptance`, `SessionPolicy`, log helper, example Android gradle)
**Risk Level:** 🟢 Low

### Context Gates

- **Roadmap** (`.ai-factory/ROADMAP.md:47`): PASS. The milestone line matches the plan exactly — plain-Dart recorder in `example/` observing `CameraPpgService`'s streams (not owning a session), accumulating `RrInterval` + metadata, one self-describing JSON per run to `getExternalStorageDirectory()`, data-layer-only, adds `path_provider`. The line names the governing spec `notes/20-calibration-capture-export.md`, which the plan follows faithfully.
- **Governing spec** (note 20): PASS. Plan mirrors the spec's lifecycle (`start`/`stop`/`save`), file location/name/schema, and guards. The plan additionally threads `CameraPpgService service` as the first `start()` param (spec wrote `start(RrAcceptance, SessionPolicy, {cameraId})`); this is a consistent refinement, not a conflict — the recorder needs the service handle to subscribe.
- **Architecture** (`.ai-factory/ARCHITECTURE.md`): PASS. Plan keeps kit `lib/` untouched, confines all new code + serialization to `example/`, and keeps kit models import-free (serialization lives in the recorder). Import allow-list in Task 2 is consistent with the plain-Dart boundary the service already enforces.
- **Rules:** no `.ai-factory/RULES.md` present — gate skipped.
- **skill-context** (`.ai-factory/skill-context/aif-review/SKILL.md`): not present — no project overrides to apply.

### Verified Against Codebase (no fantasy APIs)

- **Model fields all exist and are named exactly as the plan/JSON schema use them:**
  - `RrInterval.intervalMs`, `.isArtifact`, `.timestamp` ✓ (`lib/src/models/rr_interval.dart`). Plan correctly avoids `.timestamp` for `tMs` and uses the `Stopwatch` instead — the class doc itself warns `timestamp` is a device clock not comparable to `Stopwatch`/`DateTime.now`, exactly the note-05 caveat the plan cites.
  - `RrAcceptance.{minRrMs, consistencyThreshold, coldStartBeats, medianWindow}` ✓ — all public `final`, match Task 3's `acceptance` serialization key-for-key.
  - `SessionPolicy.{warmupDuration, targetDuration, silenceWindow, sqiFloor}` ✓ — `Duration` fields, so `.inMilliseconds` (plan) is correct, and `sqiFloor.name` is valid.
  - `SignalQuality` is an enum (`good`/`fair`/`poor`) — `.name` works; `SignalQuality.poor` exists as the plan's default-latest seed.
  - `MeasurementState.done` ✓ — the `stateStream` sentinel the recorder finalizes on.
- **`CameraPpgService` surface:** `rrStream`, `qualityStream`, `stateStream` are all public `broadcast` getters, safe for the recorder to subscribe to alongside the service's own internal fan-in — no "already listened to" risk. The recorder observing the service (not the session) honours the note-01 single-camera-owner rule.
- **`getExternalStorageDirectory()`** is the correct `path_provider` call for the app-external files dir; `path_provider` is genuinely absent from `example/pubspec.yaml`, so Task 1 is real work.
- **Pull path is accurate:** `example/android/app/build.gradle.kts` sets `applicationId = "com.mind.camera_ppg_kit_example"`, so `/sdcard/Android/data/com.mind.camera_ppg_kit_example/files/calibration/` in the plan/note is exact. App-scoped storage → no `WRITE_EXTERNAL_STORAGE`, as the plan states.
- **Log helper:** `ppgLog` exists in `example/lib/auto_detect/log.dart` — the coarse-log import in Task 2/3 is valid.

### Critical Issues

None. The plan is implementable as written.

### Minor Issues / Non-Blocking Notes

1. **`kitBpm` empty-accepted guard must short-circuit *before* the division — `double.infinity.round()` throws.** Task 3 says `kitBpm = (60000 / meanAcceptedRrMs).round()` and, for the empty-accepted case, "guard … → `null` or `0`, and keep `kitBpm` consistent." Make that guard explicit: if `acceptedIntervals == 0` (or `meanAcceptedRrMs` is `null`/`0`), set `kitBpm` directly to `null`/`0` and **do not evaluate the formula**. In Dart `60000 / 0` yields `double.infinity`, and `double.infinity.round()` throws `UnsupportedError` (it does not return a sentinel) — so a "compute then guard" ordering would crash a finger-never-present run precisely when the tester most wants the file. Low severity (the plan already flags the guard), called out only to pin the ordering.

2. **`getExternalStorageDirectory()!` null-assert is Android-only — fine for this milestone, worth a one-line note.** On iOS the call returns `null`, so the `!` would throw. The milestone is explicitly "Android file export" and the pull workflow is `adb`-only, so this is acceptable scope; flagging so the implementer doesn't later reuse the recorder on iOS without a guard.

3. **Subscribe-before-emit ordering is a note-21 (screen) contract, not a data-layer bug.** Because the service's controllers are `broadcast` (no replay), any event emitted between `startMeasurement()` and the recorder's `listen()` is lost. Task 2 subscribes synchronously inside `start()`, and the plan says the screen calls `recorder.start(...)` "at the same moment" it calls `service.startMeasurement(...)`. As long as note 21 calls `recorder.start()` **first** (it returns synchronously after wiring subscriptions) and `startMeasurement()` second, no beats are dropped. Worth restating this ordering as an explicit precondition when note 21 is planned.

4. **`durationMs` correctly survives the screen's wall-clock auto-stop.** Note 21 auto-stops at 60 s wall-clock rather than waiting for the kit's measuring-time `done`, so `stateStream` may never emit `done`. The plan handles this: `stop()` also stops the `Stopwatch` and keeps the buffer, and `save()` is callable after either `stop()` or `done`, reading `stopwatch.elapsedMilliseconds` in both paths. No gap — noted as verified.

### Positive Notes

- **Excellent codebase grounding.** Every serialized field maps to a real, correctly-named public member; the plan cites the exact note-05 device-clock caveat that motivates using `Stopwatch` for `tMs`, and that caveat is verbatim in `RrInterval`'s own doc comment.
- **Ownership boundary is correct and load-bearing.** Observing `CameraPpgService` rather than constructing a `CameraPpgSession`/controller/torch keeps the single-camera-owner invariant (note 01) intact and reuses the service's stop/start-safe broadcast controllers — the same pattern the tabbed-example plan (10) relied on.
- **Import-free-models discipline preserved.** Putting serialization in the recorder rather than on `RrAcceptance`/`SessionPolicy` respects the ARCHITECTURE rule and matches how the kit already keeps `lib/` clean.
- **Self-describing file is the right call.** Carrying the effective gate/policy params in each run makes successive default-tuning runs comparable off-device — directly serving the calibration-handoff goal (tune neiry-borrowed defaults against a manual pulse count before the Phase-10 API freeze).
- **Scope is tight and honest.** Data-layer only, no UI, no kit changes, no new permission — matches the roadmap line and defers the driving screen to note 21.

The three actionable items above are polish, not correctness blockers, and the first is already half-addressed in the plan text. The plan is solid and ready to implement.

PLAN_REVIEW_PASS
