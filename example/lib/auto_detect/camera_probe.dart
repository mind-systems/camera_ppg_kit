import 'package:camera/camera.dart';

/// A descriptor for a single rear-facing camera sensor, in the order
/// [availableCameras] enumerated it.
///
/// [CameraDescription.lensType] exists but is frequently `unknown` (especially
/// the Android logical back), so we cannot reliably rank lenses by type;
/// probe in [availableCameras] order instead.
class RearCamera {
  const RearCamera({
    required this.index,
    required this.description,
  });

  /// Zero-based position in the rear-camera sub-list (not the global camera list).
  final int index;
  final CameraDescription description;

  String get name => description.name;
  int get sensorOrientation => description.sensorOrientation;
  CameraLensType get lensType => description.lensType;

  @override
  String toString() =>
      'RearCamera(index: $index, name: $name, lensType: $lensType, '
      'sensorOrientation: $sensorOrientation°)';
}

/// Returns every rear-facing camera in the order [availableCameras] reports
/// them (default / main-wide first on iOS; single logical back on Android).
///
/// Call this once at startup or on a "Probe cameras" affordance; the result
/// drives both the device-support matrix log and the coverage round-trip.
Future<List<RearCamera>> enumerateRearCameras() async {
  final all = await availableCameras();
  final rear = all
      .where((c) => c.lensDirection == CameraLensDirection.back)
      .toList();

  return List.generate(
    rear.length,
    (i) => RearCamera(index: i, description: rear[i]),
  );
}
