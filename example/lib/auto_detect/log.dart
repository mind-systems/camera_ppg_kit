import 'dart:developer';

/// Minimal structured logger for the camera_ppg_kit example app.
/// Mirrors the nlog helper in neiry_kit/lib/src/util/nlog.dart.
void ppgLog(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  final n = DateTime.now();
  final ts =
      '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:'
      '${n.second.toString().padLeft(2, '0')}.${n.millisecond.toString().padLeft(3, '0')}';
  log('[$ts] $message',
      name: 'camera_ppg_example', error: error, stackTrace: stackTrace);
}
