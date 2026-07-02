
import 'camera_ppg_kit_platform_interface.dart';

export 'src/models/rr_interval.dart';
export 'src/models/signal_quality.dart';

class CameraPpgKit {
  Future<String?> getPlatformVersion() {
    return CameraPpgKitPlatform.instance.getPlatformVersion();
  }
}
