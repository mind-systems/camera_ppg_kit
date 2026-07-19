import 'dart:developer';

/// Kit-internal logging helper.
///
/// Mirrors `neiry_kit`'s `lib/src/util/nlog.dart` — the single internal
/// logging entry point every `lib/` file in this kit must route through.
/// Never use `print`/`debugPrint` directly: keeping all logs behind one
/// helper means the host app's own logging policy is not violated when
/// the kit is embedded. Not exported from the barrel.
void nlog(
  String message, {
  String name = 'camera_ppg_kit',
  Object? error,
  StackTrace? stackTrace,
}) {
  final n = DateTime.now();
  final ts =
      '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:'
      '${n.second.toString().padLeft(2, '0')}.${n.millisecond.toString().padLeft(3, '0')}';
  log('[$ts] $message', name: name, error: error, stackTrace: stackTrace);
}
