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

/// Logs a user interaction (button tap, navigation, toggle, retry) in the
/// example app.
///
/// Every interactive control in the example MUST call this from its handler so
/// the full sequence of user events is visible in the device logs — see the
/// "Logging" section of this repo's CLAUDE.md. Output is prefixed with `TAP →`
/// so it can be grepped out of the camera-plugin noise.
void ppgTap(String label) => ppgLog('TAP → $label');
