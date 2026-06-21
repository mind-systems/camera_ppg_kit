
import 'camera_ppg_kit_platform_interface.dart';

class CameraPpgKit {
  Future<String?> getPlatformVersion() {
    return CameraPpgKitPlatform.instance.getPlatformVersion();
  }
}
