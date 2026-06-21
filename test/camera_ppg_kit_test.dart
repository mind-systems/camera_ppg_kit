import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:camera_ppg_kit/camera_ppg_kit_platform_interface.dart';
import 'package:camera_ppg_kit/camera_ppg_kit_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockCameraPpgKitPlatform
    with MockPlatformInterfaceMixin
    implements CameraPpgKitPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final CameraPpgKitPlatform initialPlatform = CameraPpgKitPlatform.instance;

  test('$MethodChannelCameraPpgKit is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelCameraPpgKit>());
  });

  test('getPlatformVersion', () async {
    CameraPpgKit cameraPpgKitPlugin = CameraPpgKit();
    MockCameraPpgKitPlatform fakePlatform = MockCameraPpgKitPlatform();
    CameraPpgKitPlatform.instance = fakePlatform;

    expect(await cameraPpgKitPlugin.getPlatformVersion(), '42');
  });
}
