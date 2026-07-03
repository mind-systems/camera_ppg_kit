# Code Review: Motion card on the Streams tab (live values + Hz)

**Plan:** `.ai-factory/plans/32-motion-card-on-the-streams-tab-live-values-hz.md`
**Scope reviewed:** `example/lib/services/camera_ppg_service.dart`, `example/lib/providers/stream_providers.dart`, `example/lib/screens/streams_screen.dart` (example-only; no kit `lib/src/` change)
**Result:** No blocking findings. `flutter analyze` on the three changed files reports **No issues found**.

## What was checked

- **Service bridge (`camera_ppg_service.dart`).** `_motionController` is a broadcast controller added to the constructor initializer list, exposed via `motionStream`, fed from `session.motionStream` in the `_subs.addAll([...])` list, and closed in `dispose()`. This is a faithful copy of the `rrStream`/`qualityStream` bridges. Teardown ordering is correct: `dispose()` calls `stopMeasurement()` (which cancels every `_subs` entry, including the new motion bridge) **before** closing `_motionController`, so there is no add-after-close race. The barrel-only / no-`flutter` / no-`camera` invariant is preserved — `MotionSample` is already re-exported from `package:camera_ppg_kit/camera_ppg_kit.dart`, so no new import was needed. Consistent with the siblings, motion (like RR/quality) gets no terminal reset push on stop — only `_stateController` does.
- **Provider (`stream_providers.dart`).** `motionProvider` mirrors `rrProvider`/`qualityProvider` exactly; `MotionSample` resolves through the existing barrel import.
- **Screen (`streams_screen.dart`).** `_motionMeter` is a `FpsMeter` field (reused, not re-implemented, per the spec guard). `ref.listen(motionProvider, ...)` records `DateTime.now()` per emit — the `DateTime.now()` vs `sample.timestamp` choice is correct: `FpsMeter.fps` prunes its rolling window against `DateTime.now()`, while `MotionSample.timestamp` is a non-monotonic device clock, so feeding device time would age entries out immediately and peg the reading at `0.0 Hz`. `_motionCard()` gates on `motionAsync.when(...)` exactly like `_rrCard`/`_signalCard`, renders accel/gyro via `MetricRow` (exported through `widgets/widgets.dart`; `double` binds to its `num?` param; `mono: true` gives the required monospace), and appends a `'${_motionMeter.fps.toStringAsFixed(1)} Hz'` line. Card is ordered after `_signalCard()` as specified. Consumer-only discipline holds — only `ref.watch`/`ref.listen`, no session control, no `StreamBuilder`.

## Non-blocking observations

### 1. New high-frequency rebuild driver on the measurement screen (FPS-sensitivity)
`_motionCard` does `ref.watch(motionProvider)`, so the whole `StreamsScreen` `ListView` now rebuilds on **every** motion emit — and the entire point of this card is to reveal that motion may be a ~200 Hz firehose. Flutter coalesces `setState`/`markNeedsBuild` to the vsync rate, so this is bounded at ~60 fps rather than 200 fps, and the rebuilt subtree is light (a handful of `Text` rows). But it is still a new *continuous* rebuild driver on the exact screen where PPG is being measured, and `CLAUDE.md` flags the kit as **FPS-sensitive** ("heavy UI work starves the frame stream… measure on a quiet screen"). Previously this screen only rebuilt on ~1 Hz RR/quality/state changes. This is almost certainly acceptable for a dev/observation tool (and is arguably the intended way to *surface* whether throttling is needed), but worth being aware of: if the Hz readout itself perturbs the measured frame rate, that is a measurement artifact, not a device fact. No change required.

### 2. `setState(() {})` in the listener is redundant (harmless)
Because `_motionCard` already `ref.watch`es `motionProvider`, the widget is marked dirty on every emit by Riverpod regardless; the explicit `setState(() {})` in the `ref.listen` callback marks the same element dirty a second time within the same frame, which Flutter coalesces to a single rebuild. It is harmless and mirrors the file's established `_rrHistory` listener idiom, so keeping it for consistency is defensible — noting only that the Hz text would update on each emit even without it.

Neither observation blocks. The implementation matches the plan and the spec (note 44), preserves every invariant, and analyzes clean.

REVIEW_PASS
