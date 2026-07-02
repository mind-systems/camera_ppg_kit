import 'dart:async';

import 'package:camera_ppg_kit/camera_ppg_kit.dart';

import '../auto_detect/log.dart';

/// Example-app composition root for the kit's public barrel (spec note 16) —
/// the analogue of `neiry_kit`'s `NeiryService`, never part of the published
/// kit surface.
///
/// Plain Dart only: **no `flutter`, `flutter_riverpod`, `camera`, or
/// `flutter_ppg` imports** — it consumes `package:camera_ppg_kit/camera_ppg_kit.dart`
/// exclusively, which already hides those types.
///
/// Owns one [CameraPpgSession] across the Kit-API tab's lifetime, behind four
/// broadcast controllers opened in the constructor and kept open until
/// [dispose] — this mirrors `NeiryService`'s "streams stay open, fed on
/// start" pattern so Riverpod `StreamProvider`s can subscribe once and keep
/// listening across repeated measurements without a lazy-init-on-first-listen
/// bug or a `Bad state: Stream has already been listened to` on restart.
///
/// A fresh [CameraPpgSession] is created on every [startMeasurement] and torn
/// down by the matching [stopMeasurement] — the session itself is not reused
/// across measurements, only this service's own controllers are.
class CameraPpgService {
  CameraPpgService()
      : _rrController = StreamController<RrInterval>.broadcast(),
        _qualityController = StreamController<SignalQuality>.broadcast(),
        _stateController = StreamController<MeasurementState>.broadcast(),
        _fingerPresenceController =
            StreamController<FingerPresence>.broadcast();

  final StreamController<RrInterval> _rrController;
  final StreamController<SignalQuality> _qualityController;
  final StreamController<MeasurementState> _stateController;
  final StreamController<FingerPresence> _fingerPresenceController;

  /// The in-flight measurement session, or `null` when idle. A new instance
  /// is created by every [startMeasurement] call and disposed by the
  /// matching [stopMeasurement].
  CameraPpgSession? _session;

  /// Set once [dispose] has run; guards against reuse after disposal.
  bool _disposed = false;

  /// Re-entry guard for [startMeasurement] (cf. neiry's `_connecting`).
  bool _measuring = false;

  /// Fan-in subscriptions bridging [_session]'s streams into this service's
  /// long-lived controllers — wired in [startMeasurement], cancelled in
  /// [stopMeasurement].
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Broadcast stream of RR intervals, fed from the current [_session] while
  /// measuring. Stays open across stop/start cycles.
  Stream<RrInterval> get rrStream => _rrController.stream;

  /// Broadcast stream of signal-quality bands. Stays open across stop/start
  /// cycles.
  Stream<SignalQuality> get qualityStream => _qualityController.stream;

  /// Broadcast stream of measurement lifecycle transitions. Stays open
  /// across stop/start cycles.
  Stream<MeasurementState> get stateStream => _stateController.stream;

  /// Broadcast stream of finger-presence classifications. Stays open across
  /// stop/start cycles.
  Stream<FingerPresence> get fingerPresenceStream =>
      _fingerPresenceController.stream;

  /// Whether a measurement session is currently in flight.
  bool get isMeasuring => _measuring && _session != null;

  void _checkNotDisposed() {
    if (_disposed) throw StateError('CameraPpgService has been disposed');
  }

  /// Starts a new measurement: creates a fresh [CameraPpgSession], pins
  /// [cameraId] if given (skipping auto-detect), wires its streams into this
  /// service's long-lived controllers, and runs [CameraPpgSession.start].
  ///
  /// [policy]/[acceptance] are `[debug]` live-tuning knobs (spec notes 09/12)
  /// forwarded straight to the session's constructor — omit both to use the
  /// kit's internal defaults.
  ///
  /// Returns `null` on success. Returns a typed [CameraPpgError] — never
  /// throws — when the session fails to lock a sensor; the failed session is
  /// torn down before returning so a subsequent call starts clean.
  ///
  /// A no-op returning `null` immediately when a measurement is already in
  /// flight — safe to call repeatedly (e.g. a double-tapped Start button).
  Future<CameraPpgError?> startMeasurement({
    String? cameraId,
    SessionPolicy? policy,
    RrAcceptance? acceptance,
  }) async {
    _checkNotDisposed();
    if (_measuring) {
      ppgLog('CameraPpgService.startMeasurement() ignored — already measuring');
      return null;
    }
    _measuring = true;

    final session = CameraPpgSession(policy: policy, acceptance: acceptance);
    _session = session;
    if (cameraId != null) {
      session.useCamera(cameraId);
    }

    _subs.addAll([
      session.rrStream.listen(_rrController.add, onError: _rrController.addError),
      session.qualityStream.listen(_qualityController.add, onError: _qualityController.addError),
      session.stateStream.listen(_stateController.add, onError: _stateController.addError),
      session.fingerPresenceStream.listen(
        _fingerPresenceController.add,
        onError: _fingerPresenceController.addError,
      ),
    ]);

    final error = await session.start();
    if (error != null) {
      ppgLog('CameraPpgService.startMeasurement(): start() failed — ${error.type}');
      // Tear the failed session down so state resets cleanly for a retry —
      // the caller sees `isMeasuring == false` again once this returns.
      await stopMeasurement();
    }
    return error;
  }

  /// Stops the current measurement (if any) and releases the camera + torch.
  ///
  /// No-op when no measurement is in flight. This service's own broadcast
  /// controllers stay open — a subsequent [startMeasurement] re-feeds them
  /// through a fresh session.
  ///
  /// A fresh [CameraPpgSession] is created on every [startMeasurement], so
  /// [CameraPpgSession.dispose] alone (not also `stop()`) is enough to
  /// release its camera + torch — calling both would just re-run the
  /// idempotent release for nothing.
  Future<void> stopMeasurement() async {
    final session = _session;
    if (session == null) {
      _measuring = false;
      return;
    }
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _session = null;
    _measuring = false;
    await session.dispose();
  }

  /// Enumerates rear-facing cameras for the override UI, without a running
  /// measurement.
  ///
  /// Opens a transient, read-only [CameraPpgSession] purely to reach
  /// [CameraPpgSession.availableCameras] (which itself never opens a
  /// controller or the torch) and disposes it immediately — this never
  /// touches [_session] or this service's controllers/streams.
  Future<List<CameraPpgCameraInfo>> availableCameras() async {
    final session = CameraPpgSession();
    try {
      return await session.availableCameras();
    } finally {
      await session.dispose();
    }
  }

  /// Releases all resources. Idempotent — subsequent calls return
  /// immediately.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopMeasurement();
    await _rrController.close();
    await _qualityController.close();
    await _stateController.close();
    await _fingerPresenceController.close();
  }
}
