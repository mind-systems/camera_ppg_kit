
import 'camera_ppg_kit_platform_interface.dart';

export 'src/models/rr_interval.dart';
export 'src/models/signal_quality.dart';
export 'src/models/measurement_state.dart';
export 'src/models/finger_presence.dart';
export 'src/models/camera_ppg_error.dart';

class CameraPpgKit {
  Future<String?> getPlatformVersion() {
    return CameraPpgKitPlatform.instance.getPlatformVersion();
  }
}
