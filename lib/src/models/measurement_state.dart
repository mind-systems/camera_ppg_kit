/// Lifecycle of a contact-PPG measurement session.
///
/// The UI binds to this value to drive its own state machine; it is what
/// the future `CameraPpgSession.stateStream` emits.
enum MeasurementState {
  /// No measurement has been started yet.
  idle,

  /// Measurement has started and the kit is acquiring signal, but RR
  /// intervals emitted during this window are not yet trusted.
  warmup,

  /// Warm-up has completed and the kit is emitting trusted RR intervals.
  measuring,

  /// The target measurement duration has been reached and the session
  /// has ended normally.
  done,

  /// Signal or finger-presence quality is failing the acceptance gate;
  /// RR intervals should not be trusted until the state recovers.
  poorSignal,
}
