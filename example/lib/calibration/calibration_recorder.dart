import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../auto_detect/log.dart';
import '../services/camera_ppg_service.dart';

/// Captures a single calibration run's RR intervals + metadata by observing
/// an existing [CameraPpgService], and exports it to a self-describing JSON
/// file on the app external files dir (spec note 20).
///
/// Plain Dart only — it never creates a [CameraPpgSession], controller, or
/// torch itself; it strictly observes the [CameraPpgService] passed to
/// [start] so there is never a second camera owner (note 01 concurrency
/// rule). The driving screen (note 21) is expected to call [start] at the
/// same moment it calls `CameraPpgService.startMeasurement(...)`, with the
/// same [RrAcceptance]/[SessionPolicy] instances.
class CalibrationRecorder {
  RrAcceptance? _acceptance;
  SessionPolicy? _policy;
  String? _cameraId;

  DateTime _startedAt = DateTime.now();
  final Stopwatch _stopwatch = Stopwatch();

  final List<Map<String, Object?>> _records = [];
  SignalQuality _latestQuality = SignalQuality.poor;
  bool _done = false;

  /// Whether the observed session has reached [MeasurementState.done] —
  /// i.e. the buffer is finalized and [save] can be called.
  bool get isDone => _done;

  StreamSubscription<RrInterval>? _rrSub;
  StreamSubscription<SignalQuality>? _qualitySub;
  StreamSubscription<MeasurementState>? _stateSub;

  /// Starts capturing a new run: resets buffers/flags, records the effective
  /// run params, and subscribes to [service]'s `rrStream`/`qualityStream`/
  /// `stateStream`. Call this at the same moment [service].startMeasurement
  /// is called, passing the same [acceptance]/[policy] instances.
  void start(
    CameraPpgService service,
    RrAcceptance acceptance,
    SessionPolicy policy, {
    String? cameraId,
  }) {
    // Tear down a prior run's subscriptions first — otherwise a re-entrant
    // start() (e.g. a double-tapped Start) would leak the previous three
    // subscriptions and orphan them against a buffer that just got reset.
    stop();

    _records.clear();
    _latestQuality = SignalQuality.poor;
    _done = false;

    _acceptance = acceptance;
    _policy = policy;
    _cameraId = cameraId;
    _startedAt = DateTime.now();

    _stopwatch
      ..reset()
      ..start();

    _qualitySub = service.qualityStream.listen((quality) {
      _latestQuality = quality;
    });

    _rrSub = service.rrStream.listen((rr) {
      _records.add({
        'tMs': _stopwatch.elapsedMilliseconds,
        'rrMs': rr.intervalMs,
        'isArtifact': rr.isArtifact,
        'sqi': _latestQuality.name,
      });
    });

    _stateSub = service.stateStream.listen((state) {
      if (state == MeasurementState.done) {
        _stopwatch.stop();
        _done = true;
      }
    });
  }

  /// Cancels the stream subscriptions and stops the clock, keeping the
  /// buffered records for [save]. Idempotent — safe to call when never
  /// started or already stopped.
  void stop() {
    _rrSub?.cancel();
    _qualitySub?.cancel();
    _stateSub?.cancel();
    _rrSub = null;
    _qualitySub = null;
    _stateSub = null;
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
    }
  }

  /// Serializes the captured run (plus an optional manual beat count) to a
  /// fresh `calib_*.json` file under the app external files dir and returns
  /// its absolute path. Callable after [stop]/done so the tester can enter
  /// their manual count first. Each call writes a new file — nothing is
  /// overwritten.
  Future<String> save({int? countedBeats, int? countWindowSeconds}) async {
    final acceptance = _acceptance;
    final policy = _policy;
    if (acceptance == null || policy == null) {
      throw StateError('CalibrationRecorder.save() called before start()');
    }

    // Snapshot now, before the `await` below — save() may be called while
    // subscriptions are still live, and the summary must describe exactly
    // the intervals serialized, not whatever _records grows to meanwhile.
    final records = List<Map<String, Object?>>.of(_records);

    final accepted = records.where((r) => r['isArtifact'] == false).toList();
    final artifactCount = records.length - accepted.length;
    final double? meanAcceptedRrMs = accepted.isEmpty
        ? null
        : accepted.map((r) => r['rrMs']! as int).reduce((a, b) => a + b) /
            accepted.length;
    final int? kitBpm =
        meanAcceptedRrMs == null ? null : (60000 / meanAcceptedRrMs).round();

    final json = <String, Object?>{
      'schemaVersion': 1,
      'startedAt': _startedAt.toIso8601String(),
      'durationMs': _stopwatch.elapsedMilliseconds,
      'cameraId': _cameraId,
      'acceptance': {
        'minRrMs': acceptance.minRrMs,
        'consistencyThreshold': acceptance.consistencyThreshold,
        'coldStartBeats': acceptance.coldStartBeats,
        'medianWindow': acceptance.medianWindow,
      },
      'policy': {
        'warmupMs': policy.warmupDuration.inMilliseconds,
        'targetMs': policy.targetDuration.inMilliseconds,
        'silenceMs': policy.silenceWindow.inMilliseconds,
        'sqiFloor': policy.sqiFloor.name,
      },
      'manualCount': countedBeats == null
          ? null
          : {
              'beats': countedBeats,
              'windowSeconds': countWindowSeconds,
            },
      'summary': {
        'totalIntervals': records.length,
        'acceptedIntervals': accepted.length,
        'artifactIntervals': artifactCount,
        'meanAcceptedRrMs': meanAcceptedRrMs,
        'kitBpm': kitBpm,
      },
      'intervals': records,
    };

    final baseDir = await getExternalStorageDirectory();
    final dir = Directory('${baseDir!.path}/calibration');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final name = 'calib_${_fileTimestamp(_startedAt)}.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));

    ppgLog('CalibrationRecorder.save(): wrote ${file.path}');
    return file.path;
  }

  static String _fileTimestamp(DateTime dt) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}${pad2(dt.month)}${pad2(dt.day)}'
        '_${pad2(dt.hour)}${pad2(dt.minute)}${pad2(dt.second)}';
  }
}
