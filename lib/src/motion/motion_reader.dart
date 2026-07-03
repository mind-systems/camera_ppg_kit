import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../models/motion_sample.dart';
import '../util/nlog.dart';

/// Reads raw accelerometer + gyroscope events and fans out combined
/// [MotionSample]s.
///
/// Pure Dart plumbing — no `camera`/`flutter_ppg`/channel imports (follows
/// the `src/processing/` purity rule minus the models dependency). Raw
/// passthrough only: no thresholds, no stillness verdict, no rate cap.
///
/// The accelerometer tick drives the emission cadence; the gyroscope is
/// sampled-and-held — each emitted [MotionSample] carries the most recent
/// accelerometer reading paired with the most recently seen gyroscope
/// reading (defaulting to zero until the first gyro event arrives).
class MotionReader {
  final StreamController<MotionSample> _controller =
      StreamController<MotionSample>.broadcast();

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double _lastGyroX = 0.0;
  double _lastGyroY = 0.0;
  double _lastGyroZ = 0.0;

  /// Broadcast stream of combined accel + gyro samples.
  Stream<MotionSample> get samples => _controller.stream;

  /// Opens the accelerometer and gyroscope subscriptions.
  ///
  /// Synchronous by design — the caller ([CameraPpgSession.start]) invokes
  /// this from a synchronous `lockedAndStreaming = true` block with no
  /// `await`s and no staleness window; an async `start()` would introduce
  /// one.
  void start() {
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (event) {
        _lastGyroX = event.x;
        _lastGyroY = event.y;
        _lastGyroZ = event.z;
      },
      onError: (Object e, StackTrace st) {
        // Gyroscopes are genuinely absent on some devices/emulators —
        // sensors_plus surfaces that as a stream error, not a silent no-op.
        // Swallow it so a gyroscope-less device can't raise an unhandled
        // zone error; the accel side keeps emitting with held zeros.
        nlog('gyroscope stream error', error: e, stackTrace: st);
      },
    );

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (event) {
        if (_controller.isClosed) return;
        _controller.add(
          MotionSample(
            accelX: event.x,
            accelY: event.y,
            accelZ: event.z,
            gyroX: _lastGyroX,
            gyroY: _lastGyroY,
            gyroZ: _lastGyroZ,
            timestamp: event.timestamp,
          ),
        );
      },
      onError: (Object e, StackTrace st) {
        nlog('accelerometer stream error', error: e, stackTrace: st);
      },
    );
  }

  /// Cancels both sensor subscriptions and closes [samples].
  ///
  /// Idempotent — safe to call more than once. Closing the controller here
  /// (rather than leaving it to the caller) means any downstream forwarding
  /// subscription completes instead of being left subscribed to a
  /// controller that never emits again.
  Future<void> dispose() async {
    final accelSub = _accelSub;
    final gyroSub = _gyroSub;
    _accelSub = null;
    _gyroSub = null;
    await accelSub?.cancel();
    await gyroSub?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
