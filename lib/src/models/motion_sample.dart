import 'package:flutter/foundation.dart';

/// A single raw accelerometer + gyroscope reading, sampled while a
/// measurement is active.
///
/// [accelX], [accelY], [accelZ] are raw `accelerometerEventStream` readings
/// in m/s^2 — gravity is included, unfiltered. [gyroX], [gyroY], [gyroZ] are
/// the rate of rotation in rad/s.
///
/// [timestamp] is the accelerometer event's device timestamp
/// (`AccelerometerEvent.timestamp`), not a monotonic clock. Do not compare it
/// to monotonic time sources such as [Stopwatch] or [DateTime.now] drift
/// measurements.
///
/// This is a raw passthrough — no stillness verdict, no derived metric. The
/// consumer interprets the values.
@immutable
class MotionSample {
  const MotionSample({
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.timestamp,
  });

  /// Acceleration along the x axis, in m/s^2 (gravity included).
  final double accelX;

  /// Acceleration along the y axis, in m/s^2 (gravity included).
  final double accelY;

  /// Acceleration along the z axis, in m/s^2 (gravity included).
  final double accelZ;

  /// Rate of rotation around the x axis, in rad/s.
  final double gyroX;

  /// Rate of rotation around the y axis, in rad/s.
  final double gyroY;

  /// Rate of rotation around the z axis, in rad/s.
  final double gyroZ;

  /// Device timestamp of the accelerometer event that produced this sample.
  final DateTime timestamp;
}
