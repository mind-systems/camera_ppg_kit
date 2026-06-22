import 'package:flutter/material.dart';

import 'auto_detect/auto_detect_screen.dart';

void main() {
  // Required before availableCameras() and any other plugin calls.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CameraPpgKitExampleApp());
}

class CameraPpgKitExampleApp extends StatelessWidget {
  const CameraPpgKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera PPG Kit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AutoDetectScreen(),
    );
  }
}
