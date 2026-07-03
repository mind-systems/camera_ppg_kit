/// Example-side lifecycle for "what the source is doing right now" — owned
/// by [CameraPpgService] (see `camera_ppg_service.dart`), not by the kit.
///
/// The kit's public `MeasurementState` (spec notes 19/23) is frozen at four
/// values — `idle`, `warmup`, `measuring`, `poorSignal` — and deliberately
/// carries no representation of the async transitions around it: the
/// probe/open round-trip inside `startMeasurement()` and the
/// stop-stream/dispose-isolate/torch-off/dispose-controller teardown inside
/// `stopMeasurement()` (which can be slow or hang on `camera_android_camerax`,
/// see the kit's `CLAUDE.md`). Without an explicit state for those windows,
/// the UI shows the *previous* state and its buttons in the wrong
/// enabled/disabled combination, so a slow stop reads as a frozen "Measuring"
/// (spec note 33).
///
/// `SourceLifecycle` wraps the kit's `MeasurementState` and adds `starting`
/// and `stopping` for exactly those windows:
///
/// `idle → starting → warmup → measuring ⇄ poorSignal → stopping → idle`
///
/// This enum must **never** be added to the kit's public `MeasurementState`
/// — it is an example-only concept (spec notes 33/19/23). There is also no
/// terminal `done`/"Complete" state (note 23): the only path back to `idle`
/// is `stopping → idle`.
enum SourceLifecycle {
  idle,
  starting,
  warmup,
  measuring,
  poorSignal,
  stopping;

  /// The source is actively producing a live signal — i.e. the kit's running
  /// `MeasurementState` values folded in while measuring.
  bool get isActive =>
      this == SourceLifecycle.warmup ||
      this == SourceLifecycle.measuring ||
      this == SourceLifecycle.poorSignal;

  /// An async transition is in flight (`startMeasurement()`/`stopMeasurement()`
  /// entered but not yet settled) — screens should disable Start/Stop and show
  /// a spinner instead of gating on a stale prior state.
  bool get isTransitional =>
      this == SourceLifecycle.starting || this == SourceLifecycle.stopping;
}
