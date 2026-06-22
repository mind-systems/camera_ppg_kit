import 'camera_probe.dart';

/// Reason a coverage round-trip failed to lock a camera.
enum AutoDetectError {
  /// No rear sensor read as covered during the probe pass.
  noCoveredCamera,

  /// A [CameraException] occurred that was not a permission denial.
  cameraError,

  /// The OS denied camera access.
  permissionDenied,
}

/// Per-camera record collected during the coverage round-trip.
class CameraProbeRecord {
  const CameraProbeRecord({
    required this.camera,
    required this.framesSeen,
    required this.coveredFrames,
    required this.covered,
  });

  final RearCamera camera;

  /// Total [PPGSignal] frames evaluated during the dwell window.
  final int framesSeen;

  /// Frames whose rawIntensity satisfied the coverage test.
  final int coveredFrames;

  /// True if covered-fraction met the acceptance threshold.
  final bool covered;

  double get coveredFraction =>
      framesSeen == 0 ? 0.0 : coveredFrames / framesSeen;

  @override
  String toString() =>
      'CameraProbeRecord(camera: ${camera.name}, frames: $framesSeen, '
      'coveredFrames: $coveredFrames, fraction: ${coveredFraction.toStringAsFixed(2)}, '
      'covered: $covered)';
}

/// Result of [detectCoveredCamera].
///
/// On success, [lockedCamera] holds the first camera whose finger-presence
/// test passed. [records] contains a [CameraProbeRecord] for every camera
/// that was probed before the round-trip ended.
class CoverageOutcome {
  const CoverageOutcome._({
    this.lockedCamera,
    this.error,
    required this.records,
  });

  /// Success: locked on the first covered camera.
  const CoverageOutcome.success({
    required RearCamera lockedCamera,
    required List<CameraProbeRecord> records,
  }) : this._(lockedCamera: lockedCamera, records: records);

  /// Failure: describes what went wrong.
  const CoverageOutcome.failure({
    required AutoDetectError error,
    required List<CameraProbeRecord> records,
  }) : this._(error: error, records: records);

  final RearCamera? lockedCamera;
  final AutoDetectError? error;
  final List<CameraProbeRecord> records;

  bool get isSuccess => lockedCamera != null;
}
