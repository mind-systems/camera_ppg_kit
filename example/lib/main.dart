import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auto_detect/auto_detect_screen.dart';
import 'auto_detect/log.dart';
import 'providers/camera_ppg_service_provider.dart';
import 'screens/kit_api_tab.dart';

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
      home: const _TabShell(),
    );
  }
}

/// Two-tab shell: **Raw** (Tab 1, direct `flutter_ppg`/`camera` — the
/// existing Phase-2 panels, unchanged) and **Kit API** (Tab 2, kit-barrel
/// dogfood, spec note 14).
///
/// Owns an explicit [TabController] (not [DefaultTabController]) so it can
/// listen for tab changes: the rear camera + torch cannot be opened
/// concurrently (CLAUDE.md note 01), and both tabs can drive it — Tab 1 via
/// direct `flutter_ppg`/`camera` access, Tab 2 via [CameraPpgService]. This
/// shell makes **the active tab own the camera**: when the selection leaves
/// Tab 2, it releases the camera + torch (`stopMeasurement()`) so Tab 1's
/// direct `CameraController` open cannot collide with a still-live one
/// (plan-review Issues 1 & 2). The service's own broadcast controllers stay
/// open across this release (the "streams stay open" invariant, spec note
/// 16) — returning to Tab 2 keeps the same provider subscriptions; the user
/// just presses Start again to resume.
class _TabShell extends ConsumerStatefulWidget {
  const _TabShell();

  @override
  ConsumerState<_TabShell> createState() => _TabShellState();
}

class _TabShellState extends ConsumerState<_TabShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Tracks the last-seen tab index so [_onTabChanged] reacts once per
  /// actual transition rather than on every animation tick the
  /// [TabController] listener fires during a swipe.
  int _previousIndex = 0;

  static const int _kitApiTabIndex = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    final index = _tabController.index;
    if (index == _previousIndex) return;
    final leftKitApiTab = _previousIndex == _kitApiTabIndex && index != _kitApiTabIndex;
    _previousIndex = index;
    if (!leftKitApiTab) return;

    ppgLog('Tab shell: left Kit API tab — releasing camera/torch');
    // Not awaited — a TabController listener can't be async. The ordered
    // release (stop image stream -> dispose isolate -> torch off -> dispose
    // controller) takes hundreds of ms, so a user who switches here and
    // immediately triggers Tab 1's auto-detect could in principle race a
    // still-closing controller into a `CameraException`. Tab 1 only opens
    // the camera on an explicit "Start" tap (never on tab entry), so normal
    // human reaction time makes this unlikely in practice — a known,
    // accepted residual race, not a fix owed here (review finding 2).
    ref.read(cameraPpgServiceProvider).stopMeasurement();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera PPG Kit'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Raw'),
            Tab(text: 'Kit API'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          AutoDetectScreen(),
          KitApiTab(),
        ],
      ),
    );
  }
}
