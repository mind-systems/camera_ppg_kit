import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auto_detect/auto_detect_screen.dart';
import 'auto_detect/log.dart';
import 'providers/camera_ppg_service_provider.dart';
import 'screens/calibration_screen.dart';
import 'screens/streams_screen.dart';
import 'screens/source_screen.dart';

void main() {
  // Required before availableCameras() and any other plugin calls.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CameraPpgKitExampleApp()));
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
      home: const _Shell(),
    );
  }
}

/// Named branch identity (spec note 22 / Task 3) — never a magic index.
/// [_ShellState] builds both the [IndexedStack] children and the
/// [NavigationBar] destinations from this enum, and gates the Raw-exclusivity
/// hook on `_Branch.raw` rather than a literal index, so inserting a
/// Calibration branch before Raw (a future milestone, note 21) is a one-line,
/// index-shift-safe change.
enum _Branch {
  source('Source'),
  streams('Streams'),
  calibration('Calibration'),
  raw('Raw');

  const _Branch(this.title);

  final String title;
}

/// Maps a branch to its screen — the single place that keeps the
/// [IndexedStack] children in sync with [_Branch]. Both `children` (below)
/// and `destinations` are built by iterating `_Branch.values` through this
/// switch/enum, so inserting a branch (e.g. Calibration before Raw, note 21)
/// only requires adding an enum case and a switch arm here — never a
/// positional edit to a separate hardcoded widget list.
Widget _screenFor(_Branch branch) => switch (branch) {
      _Branch.source => const SourceScreen(),
      _Branch.streams => const StreamsScreen(),
      _Branch.calibration => const CalibrationScreen(),
      _Branch.raw => const AutoDetectScreen(),
    };

/// All-mounted shell: **Source** (the sole Start/Stop control), **Streams**
/// (pure consumer), and **Raw** (direct `flutter_ppg`/`camera` — the
/// existing Phase-2 panels, unchanged) — spec note 22.
///
/// Every branch is a child of a single [IndexedStack], so switching among
/// them never disposes a screen or drops its provider subscriptions — the
/// [CameraPpgService] singleton is the sole owner of the source lifecycle,
/// and navigation alone never stops measurement or breaks streams (the
/// load-bearing property this shell replaces `_TabShell`'s
/// "leaving Kit-API → stop" rule with).
///
/// The one exception is the **Raw** branch: it opens the camera directly
/// (kit-bypass, note 14), and the rear camera + torch cannot be opened
/// concurrently (note 01). So the shell keeps exactly one narrow navigation
/// hook: selecting Raw stops the kit source first.
class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  _Branch _selected = _Branch.source;

  void _onDestinationSelected(int index) {
    final branch = _Branch.values[index];
    ppgTap('nav:${branch.name}');
    if (branch == _Branch.raw) {
      // Not awaited — a `NavigationBar` callback can't be async. The ordered
      // release (stop image stream -> dispose isolate -> torch off -> dispose
      // controller) still takes hundreds of ms and can run past this call
      // returning, but that no longer leaves a race for a following Start to
      // land in: `stopMeasurement()` flips the shared lifecycle to
      // `SourceLifecycle.stopping` synchronously on entry (spec note 33), and
      // the Source screen gates its Start button on `lifecycle == idle`. So a
      // Start fired mid-teardown is closed by gating here, not by awaiting.
      ppgLog('Shell: entering Raw — releasing kit source camera/torch');
      ref.read(cameraPpgServiceProvider).stopMeasurement();
    }
    setState(() => _selected = branch);
  }

  @override
  Widget build(BuildContext context) {
    final index = _selected.index;
    return Scaffold(
      appBar: AppBar(title: Text(_selected.title)),
      body: IndexedStack(
        index: index,
        children: [for (final branch in _Branch.values) _screenFor(branch)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          for (final branch in _Branch.values)
            NavigationDestination(
              icon: const Icon(Icons.circle_outlined),
              selectedIcon: const Icon(Icons.circle),
              label: branch.title,
            ),
        ],
      ),
    );
  }
}
