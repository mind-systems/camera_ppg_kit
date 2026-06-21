import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'camera_ppg_kit_method_channel.dart';

abstract class CameraPpgKitPlatform extends PlatformInterface {
  /// Constructs a CameraPpgKitPlatform.
  CameraPpgKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static CameraPpgKitPlatform _instance = MethodChannelCameraPpgKit();

  /// The default instance of [CameraPpgKitPlatform] to use.
  ///
  /// Defaults to [MethodChannelCameraPpgKit].
  static CameraPpgKitPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [CameraPpgKitPlatform] when
  /// they register themselves.
  static set instance(CameraPpgKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
