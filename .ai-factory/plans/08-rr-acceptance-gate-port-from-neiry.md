# Plan: RR acceptance gate (port from neiry)

## Context
Port neiry's `_gate()` artifact logic (hard 300 ms floor, no upper bound, rolling-median consistency, 3-beat cold-start grace) into a pure-Dart `RrAcceptance` class, wired into `CameraPpgSession` so peak-halving intervals that leak past `flutter_ppg`'s own outlier filter are flagged as `RrInterval.isArtifact` before reaching consumers.

## Settings
- Testing: yes
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Acceptance gate

- [x] **Task 1: Create the pure `RrAcceptance` gate**
  Files: `lib/src/processing/rr_acceptance.dart`
  New pure-Dart file in `src/processing/`. Import **only** `../models/rr_interval.dart` — zero Flutter / `camera` / `flutter_ppg` / channel imports (ARCHITECTURE.md rule 3/4: `src/processing/` depends on `src/models/` only, stays isolate-safe and unit-testable). Do **not** export it from the `camera_ppg_kit.dart` barrel — it is internal, mirroring `session_policy.dart`.

  Stateful class `RrAcceptance` with constructor params copied from neiry's `PpgPeakDetector` gate fields (keep the same names/defaults so both kits read alike):
  - `int minRrMs = 300` — hard lower bound; `intervalMs < minRrMs → artifact`.
  - `double consistencyThreshold = 0.40` — >40% deviation from rolling median → artifact.
  - `int coldStartBeats = 3` — first 3 beats accepted unconditionally to seed the median.
  - `int medianWindow = 5` — rolling history size.

  Do **NOT** port any peak-detection state — `flutter_ppg` owns that here. Specifically drop neiry's `refractoryMs`, `bufferDurationMs`, `_buffer`, `_lastPeakTs`, `_lastPpiMs`, `_currentRefractory`, `_findPeaks`, and `processBatch`. Keep only the rolling history `final List<int> _rrHistory = []`.

  Public API:
  - `RrInterval evaluate(RrInterval rr)` — computes artifact status via the private `_gate(rr.intervalMs)`, appends **only non-artifact** beats to `_rrHistory` (cap at `medianWindow`, evict oldest — so artifacts never poison the median, matching neiry lines 116–122), and returns a copy of `rr` with `isArtifact` set. `RrInterval` has no `copyWith`, so construct a new one: `RrInterval(intervalMs: rr.intervalMs, timestamp: rr.timestamp, isArtifact: artifact)`.
  - `void reset()` — `_rrHistory.clear()` so cold-start re-seeds on the next measurement (mirrors neiry's reset-after-silence contract).

  Private `bool _gate(int rrMs)` — port neiry `ppg_peak_detector.dart` lines 213–225 verbatim in spirit:
  1. `if (rrMs < minRrMs) return true;` — hard lower bound, **no upper bound** (extreme bradycardia >2000 ms must survive; do not rely on `flutter_ppg`'s clamp).
  2. `if (_rrHistory.length < coldStartBeats) return false;` — cold-start grace.
  3. Compute median of sorted `_rrHistory` (`sorted[sorted.length ~/ 2].toDouble()`); `return (rrMs - median).abs() / median > consistencyThreshold;`.

  Add a class doc comment noting it layers on top of `flutter_ppg`'s window-statistic outlier filter (it does not replace it) and that it is stateful — one instance per measurement, never per beat.

### Phase 2: Wire into the session

- [x] **Task 2: Route RR intervals through the gate in `CameraPpgSession`** (depends on Task 1)
  Files: `lib/src/api/camera_ppg_session.dart`
  Add `import '../processing/rr_acceptance.dart';`.
  - Constructor: add an optional injectable param mirroring the existing `SessionPolicy? policy` pattern — `CameraPpgSession({SessionPolicy? policy, RrAcceptance? acceptance})`, storing `_acceptance = acceptance ?? RrAcceptance()` in a `final RrAcceptance _acceptance` field. This keeps the ctor path open for the Phase-7 example live-tuning / tests without adding host config now.
  - In `_onSignal` (currently ~lines 494–508), replace the passthrough `RrInterval(..., isArtifact: false)` emit: for each `rr` in `newIntervals`, build `RrInterval(intervalMs: rr.round(), timestamp: signal.timestamp, isArtifact: false)`, pass it through `_acceptance.evaluate(...)`, and add the returned interval to `_rrController`. Keep the existing `_policy.rrTrusted` guard and `_rrController.isClosed` check exactly as-is — the gate only sets `isArtifact`, it never withholds a beat. Update/remove the stale comment on line ~468 that says artifact detection "lands in the Phase-6 acceptance gate", since it now lives here.
  - Feed the gate every trusted interval, artifact or not — do not pre-filter before `evaluate`; the gate's own history-append logic already skips artifacts.
  - In `_release()` (the single teardown that `stop()` calls), add `_acceptance.reset();` so cold-start grace re-arms for the next measurement, alongside the existing `_stopwatch.stop()`.

### Phase 3: Unit tests

- [x] **Task 3: Unit-test the gate** (depends on Task 1)
  Files: `test/rr_acceptance_test.dart`
  Pure-Dart tests, no hardware, synthetic `RrInterval` sequences (follow the structure of `test/session_policy_test.dart`). Use a fixed `DateTime` for `timestamp`. Assert on the returned `isArtifact`. Cover the note-12 cases:
  - First 3 beats accepted even at extreme HR (e.g. three 3500 ms intervals → all `isArtifact == false`).
  - `intervalMs = 250` → artifact regardless of history (hard lower bound).
  - `intervalMs = 4000` (bradycardia) after a seeded ~3000 ms median → **not** artifact (proves no upper bound).
  - A +50% spike off a stable seeded median → artifact, and a following in-range beat is **not** artifact (proves the spike was excluded from the median — history not poisoned).
  - After `reset()`, the next 3 beats are again accepted unconditionally (cold-start re-armed).
