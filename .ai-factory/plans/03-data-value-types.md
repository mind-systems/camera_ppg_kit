# Plan: Data value types

## Context
Add the kit's two primary output value types — `RrInterval` (shape-identical to `neiry_kit`'s `RRInterval`) and `SignalQuality` (good/fair/poor + `fromSnr` factory) — so both camera and worn sources feed `mind_mobile`'s single RR-interval source contract. Pure Dart value types with no BPM/HRV; the consumer derives those.

## Settings
- Testing: yes (spec explicitly requires unit tests for `fromSnr` thresholds)
- Logging: none (pure value types)
- Docs: no

## Notes for the implementer
- **Field shape is load-bearing.** Follow the spec note (`.ai-factory/notes/05-data-value-types.md`) and neiry's actual class (`neiry_kit/lib/src/models/rr_interval.dart`): constructor is `RrInterval({required int intervalMs, required DateTime timestamp, bool isArtifact = false})`. Field names must be `intervalMs` / `timestamp` / `isArtifact` — do **not** rename to `rrMs`/`milliseconds`/`durationMs`. (The illustrative snippet in `ARCHITECTURE.md` using `milliseconds:`/`quality:` is outdated — the spec note and neiry's real type win.)
- `RrInterval` carries **no** quality field — quality is a separate stream/type. Keep the two models independent.
- The barrel `lib/camera_ppg_kit.dart` currently only defines the scaffold `CameraPpgKit` class and exports nothing from `src/`. Add `export` lines without removing the existing scaffold.
- SNR→enum thresholds come from spike distributions that aren't finalized yet; encode them as named constants with clear provisional values so calibration (note 02) can tune them in one place.

## Tasks

### Phase 1: Value types

- [x] **Task 1: Add `RrInterval` model**
  Files: `lib/src/models/rr_interval.dart`
  Port neiry's `RRInterval` verbatim in spirit as `RrInterval`: `@immutable` class, `const` constructor with `required int intervalMs`, `required DateTime timestamp`, `bool isArtifact = false`. Copy neiry's doc comments (`neiry_kit/lib/src/models/rr_interval.dart`): `timestamp` is wall-clock of the later peak and is **not** monotonic (don't compare to `Stopwatch`/`DateTime.now` drift); `isArtifact: true` ticks must never be used for animation or HRV. No BPM/HRV fields, no quality field.

- [x] **Task 2: Add `SignalQuality` model + `fromSnr` factory**
  Files: `lib/src/models/signal_quality.dart`
  Define `enum SignalQuality { good, fair, poor }`. Add a static `SignalQuality.fromSnr(double snr)` factory that maps an SNR value onto the enum via named threshold constants (e.g. `_goodSnrThreshold`, `_fairSnrThreshold`) declared at the top of the file so they are tunable in one place. Pick concrete provisional defaults and mark them clearly as provisional/spike-tunable in a doc comment (referencing note 02). Define the boundary behavior explicitly (document whether each threshold is inclusive `>=`) so Task 4 can assert exact boundary results. Handle degenerate SNR (e.g. `NaN`/negative) by returning `poor`.

### Phase 2: Surface + tests

- [x] **Task 3: Export both models from the barrel** (depends on Task 1, Task 2)
  Files: `lib/camera_ppg_kit.dart`
  Add `export 'src/models/rr_interval.dart';` and `export 'src/models/signal_quality.dart';` to the public barrel, keeping the existing `CameraPpgKit` scaffold class intact. Do not export anything from `src/channel`, `src/processing`, or `src/util`.

- [x] **Task 4: Unit-test `fromSnr` thresholds and `RrInterval` construction** (depends on Task 1, Task 2)
  Files: `test/models_test.dart`
  Add tests asserting: `RrInterval` construction and field values (including `isArtifact` default `false`); `SignalQuality.fromSnr` returns the correct band on each side of **both** threshold boundaries (at, just-below, just-above each constant) matching the inclusivity documented in Task 2; and that degenerate SNR (`NaN`/negative) yields `poor`. Import via the public barrel (`package:camera_ppg_kit/camera_ppg_kit.dart`).
