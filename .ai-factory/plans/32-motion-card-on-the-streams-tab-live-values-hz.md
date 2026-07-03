# Plan: Motion card on the Streams tab (live values + Hz)

## Context
Surface the kit's raw `motionStream` (note 43) on the example's Streams tab: a new "Motion" card showing live accel/gyro values plus a real-time sample-rate (Hz) readout, so the developer can watch the actual device throughput and decide whether throttling is warranted.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Service + provider bridge

- [x] **Task 1: Fan `session.motionStream` through the example service**
  Files: `example/lib/services/camera_ppg_service.dart`
  Add a long-lived `_motionController = StreamController<MotionSample>.broadcast()` initialized in the constructor (mirror the existing `_rrController`/`_qualityController` fields and their initializer-list entries). Expose `Stream<MotionSample> get motionStream => _motionController.stream` alongside the other stream getters, with a dartdoc matching their "stays open across stop/start cycles" wording. In `startMeasurement`, add a bridge line to the `_subs.addAll([...])` list: `session.motionStream.listen(_motionController.add, onError: _motionController.addError)` — mirror the `rrStream`/`qualityStream` bridges exactly (no lifecycle folding, raw passthrough). In `dispose`, add `await _motionController.close()` next to the other controller closes. `MotionSample` is already exported from the kit barrel — no new import beyond the existing `package:camera_ppg_kit/camera_ppg_kit.dart`. Keep the file's no-`flutter`/no-`camera` invariant intact.

- [x] **Task 2: Add `motionProvider`** (depends on Task 1)
  Files: `example/lib/providers/stream_providers.dart`
  Add `final motionProvider = StreamProvider<MotionSample>((ref) => ref.watch(cameraPpgServiceProvider).motionStream);`, mirroring `rrProvider`/`qualityProvider`. Add a one-line dartdoc noting it is a raw device-motion passthrough (accel/gyro), interpretation left to the consumer. `MotionSample` resolves through the existing barrel import.

### Phase 2: Streams tab card

- [x] **Task 3: Add `_motionCard` with live values + Hz readout** (depends on Task 2)
  Files: `example/lib/screens/streams_screen.dart`
  Reuse the existing `ref.listen` + `setState` pattern already used for `_rrHistory`:
  - Add a `final FpsMeter _motionMeter = FpsMeter();` field on `_StreamsScreenState` (import `../common/fps_meter.dart`).
  - In `build`, add a `ref.listen<AsyncValue<MotionSample>>(motionProvider, (prev, next) { next.whenData((sample) { _motionMeter.record(DateTime.now()); setState(() {}); }); });` alongside the existing `ref.listen` calls. Use `DateTime.now()` — **not** `sample.timestamp` — because `FpsMeter.fps` prunes its window against `DateTime.now()` and `MotionSample.timestamp` is an explicitly non-monotonic device clock (see its dartdoc); mixing the two clock domains would corrupt the rolling-window Hz reading. `setState(() {})` re-renders so the Hz text tracks each emit.
  - Add a `Widget _motionCard()` returning a `SectionCard(title: 'Motion', child: ...)` that does `final motionAsync = ref.watch(motionProvider);` then `motionAsync.when(data: ..., loading: () => const AsyncEmpty('waiting for signal…'), error: (e, _) => AsyncError(e))`, gating on the `AsyncValue` exactly like `_rrCard`/`_signalCard`. In the `data` arm render accel x/y/z and gyro x/y/z (monospace, e.g. `LabelRow` rows or a monospace `Text`, formatted to a fixed number of decimals) plus a Hz readout line showing `'${_motionMeter.fps.toStringAsFixed(1)} Hz'`.
  - Add `const SizedBox(height: 16), _motionCard(),` to the `ListView` children, ordered **after** `_signalCard()`.
  Consumer-only: no session control, no `startMeasurement`/`stopMeasurement`, no `StreamBuilder`/per-widget `.listen()` — only `ref.watch`/`ref.listen`. Keep the barrel-only import discipline (`MotionSample` comes from `package:camera_ppg_kit/camera_ppg_kit.dart`).
