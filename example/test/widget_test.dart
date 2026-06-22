import 'package:flutter_test/flutter_test.dart';

import 'package:camera_ppg_kit_example/main.dart';

void main() {
  testWidgets('App launches with AutoDetectScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const CameraPpgKitExampleApp());

    // Guidance text is part of the widget tree and renders synchronously.
    // The background _enumerate() call may throw MissingPluginException on the
    // test host (no camera plugin registered) — caught in _enumerate(), so it
    // does not escape to the test zone.
    expect(find.textContaining('Place a finger'), findsOneWidget);

    // Drain the pending enumeration microtask so the test zone is clean.
    await tester.pump();
  });
}
