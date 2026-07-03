import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../auto_detect/log.dart';
import '../providers/camera_ppg_service_provider.dart';
import '../providers/session_config_provider.dart';
import '../providers/stream_providers.dart';

/// Source branch — the **sole** screen that issues
/// `service.startMeasurement()` / `stopMeasurement()`, mirroring neiry's
/// `device_screen` (spec note 22). Kit-API and Raw are pure consumers; only
/// this screen commands the [CameraPpgService] singleton, which still owns
/// the session across navigation (the shell keeps every branch mounted).
///
/// Carries the camera-permission flow, camera override, and the `[debug]`
/// tuning panel — all relocated here from `streams_screen.dart` (Task 4 strips
/// them there). The tuning panel seeds from and writes to
/// [sessionConfigProvider] so the config it starts with is always the same
/// one the future calibration screen will read (note 21).
class SourceScreen extends ConsumerStatefulWidget {
  const SourceScreen({super.key});

  @override
  ConsumerState<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends ConsumerState<SourceScreen> {
  // ── Camera override ───────────────────────────────────────────────────
  List<CameraPpgCameraInfo> _cameras = [];
  String? _selectedCameraId;
  bool _loadingCameras = false;

  // ── Start/stop outcome ────────────────────────────────────────────────
  CameraPpgError? _lastError;

  bool _debugExpanded = false;

  @override
  void initState() {
    super.initState();
    // Deferred rather than called directly: mounting this screen inside the
    // shell's `IndexedStack` can happen during the shell's own build/layout
    // pass, and `_loadCameras`'s synchronous pre-await `setState()` can trip
    // a "setState() called during build" assertion if it runs inline from
    // `initState` in that window. A post-frame callback runs it once the
    // current build/layout has finished instead (mirrors streams_screen).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCameras());
  }

  Future<void> _loadCameras() async {
    setState(() => _loadingCameras = true);
    final cameras = await ref.read(cameraPpgServiceProvider).availableCameras();
    if (!mounted) return;
    setState(() {
      _cameras = cameras;
      _loadingCameras = false;
      // Drop a selection the refreshed enumeration no longer contains —
      // otherwise DropdownButton asserts that its `value` matches exactly
      // one item.
      if (_selectedCameraId != null && !_cameras.any((c) => c.id == _selectedCameraId)) {
        _selectedCameraId = null;
      }
    });
  }

  void _selectCamera(String? id) {
    ppgTap('source_camera_override:${id ?? "auto"}');
    setState(() => _selectedCameraId = id);
  }

  /// Requests camera permission and reports whether `_start()` may proceed.
  ///
  /// Mirrors neiry's `_scan()` permission flow: granted → proceed; denied →
  /// surface a retryable error; permanently denied/restricted → deep-link to
  /// app settings and surface the permanently-denied error variant so the
  /// existing `_errorBanner` shows the settings guidance line. Never calls
  /// `startMeasurement()` itself — the caller decides what "proceed" means.
  Future<bool> _checkAndRequestCameraPermission() async {
    ppgTap('source_permission_request');
    final status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied || status.isRestricted) {
      ppgTap('source_permission_open_settings');
      await openAppSettings();
      if (!mounted) return false;
      setState(() {
        _lastError = CameraPpgError.permissionDenied(permanentlyDenied: true);
      });
      return false;
    }
    if (!mounted) return false;
    setState(() => _lastError = CameraPpgError.permissionDenied());
    return false;
  }

  Future<void> _start() async {
    ppgTap('source_start');
    if (!await _checkAndRequestCameraPermission()) return;
    if (!mounted) return;
    setState(() => _lastError = null);
    final service = ref.read(cameraPpgServiceProvider);
    final config = ref.read(sessionConfigProvider);
    final error = await service.startMeasurement(
      cameraId: _selectedCameraId,
      policy: config.policy,
      acceptance: config.acceptance,
    );
    if (!mounted) return;
    setState(() => _lastError = error);
  }

  Future<void> _stop() async {
    ppgTap('source_stop');
    await ref.read(cameraPpgServiceProvider).stopMeasurement();
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(stateProvider);
    final state = stateAsync.value ?? MeasurementState.idle;
    final isRunning = state == MeasurementState.warmup ||
        state == MeasurementState.measuring ||
        state == MeasurementState.poorSignal;
    final canStop = state != MeasurementState.idle;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stateBanner(state),
          const SizedBox(height: 12),
          if (_lastError != null) ...[
            _errorBanner(_lastError!),
            const SizedBox(height: 12),
          ],
          _startStopRow(isRunning: isRunning, canStop: canStop),
          const SizedBox(height: 16),
          _qualityAndPresenceRow(),
          const SizedBox(height: 16),
          _cameraOverrideSection(isRunning),
          const SizedBox(height: 16),
          _debugPanel(),
        ],
      ),
    );
  }

  Widget _stateBanner(MeasurementState state) {
    final (label, color) = switch (state) {
      MeasurementState.idle => ('Idle', Colors.grey),
      MeasurementState.warmup => ('Hold still… warming up', Colors.blue),
      MeasurementState.measuring => ('Measuring', Colors.green),
      MeasurementState.poorSignal => ('Poor signal — check finger placement', Colors.orange),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _errorBanner(CameraPpgError error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${error.type.name}${error.message != null ? ' — ${error.message}' : ''}',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          if (error.permanentlyDenied)
            const Text('Permission permanently denied — grant it in system settings.',
                style: TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              ppgTap('source_retry');
              _start();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _startStopRow({
    required bool isRunning,
    required bool canStop,
  }) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: isRunning ? null : () => _start(),
            child: const Text('Start'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: canStop ? _stop : null,
            child: const Text('Stop'),
          ),
        ),
      ],
    );
  }

  /// Source status — its **own copy** of the status display, so the operator
  /// confirms the source is live before navigating to a consumer screen.
  /// Kit-API keeps an identical copy (Scope notes) — deliberately not
  /// factored into a shared widget.
  Widget _qualityAndPresenceRow() {
    final quality = ref.watch(qualityProvider).value;
    final presence = ref.watch(fingerPresenceProvider).value;

    final qualityColor = switch (quality) {
      SignalQuality.good => Colors.green,
      SignalQuality.fair => Colors.orange,
      SignalQuality.poor => Colors.red,
      null => Colors.grey,
    };
    final presenceLabel = switch (presence) {
      FingerPresence.present => 'finger present',
      FingerPresence.absent => 'no finger',
      FingerPresence.overBright => 'over-bright (not covering flash)',
      null => 'unknown',
    };

    return Row(
      children: [
        Chip(
          label: Text('SQI: ${quality?.name ?? '—'}'),
          backgroundColor: qualityColor.withValues(alpha: 0.15),
          labelStyle: TextStyle(color: qualityColor, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(presenceLabel, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  /// Lets the developer pin a rear sensor via [CameraPpgSession.useCamera]
  /// (through the service), or leave it on auto-detect (the default).
  ///
  /// Does not show which sensor auto-detect itself locked — the current
  /// barrel exposes no such accessor (`CameraPpgSession` surfaces only
  /// `rrStream`/`qualityStream`/`stateStream`/`fingerPresenceStream`, never
  /// the resolved `CameraDescription`); adding one is a kit-surface change
  /// outside this example-only task.
  Widget _cameraOverrideSection(bool isRunning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Camera override', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (_loadingCameras)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: isRunning
                    ? null
                    : () {
                        ppgTap('source_refresh_cameras');
                        _loadCameras();
                      },
                child: const Text('Refresh'),
              ),
          ],
        ),
        DropdownButton<String?>(
          isExpanded: true,
          value: _selectedCameraId,
          hint: const Text('Auto-detect (signal-based)'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Auto-detect (signal-based)'),
            ),
            for (final cam in _cameras)
              DropdownMenuItem<String?>(
                value: cam.id,
                child: Text('${cam.id} (${cam.lensType})'),
              ),
          ],
          onChanged: isRunning ? null : _selectCamera,
        ),
      ],
    );
  }

  Widget _debugPanel() {
    final config = ref.watch(sessionConfigProvider);
    final notifier = ref.read(sessionConfigProvider.notifier);
    final policy = config.policy;
    final acceptance = config.acceptance;

    return Card(
      child: ExpansionTile(
        title: const Text('[debug] tuning', style: TextStyle(fontWeight: FontWeight.bold)),
        initiallyExpanded: _debugExpanded,
        onExpansionChanged: (v) => setState(() => _debugExpanded = v),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Session policy (note 09)', style: TextStyle(fontWeight: FontWeight.bold)),
                _intField('Warm-up (s)', policy.warmupDuration.inSeconds, notifier.setWarmupSeconds),
                _intField('Silence window (s)', policy.silenceWindow.inSeconds, notifier.setSilenceSeconds),
                Row(
                  children: [
                    const Text('SQI floor:'),
                    const SizedBox(width: 8),
                    DropdownButton<SignalQuality>(
                      value: policy.sqiFloor,
                      items: [
                        for (final q in SignalQuality.values)
                          DropdownMenuItem(value: q, child: Text(q.name)),
                      ],
                      onChanged: (v) {
                        if (v != null) notifier.setSqiFloor(v);
                      },
                    ),
                  ],
                ),
                const Divider(),
                const Text('RR-gate (note 12)', style: TextStyle(fontWeight: FontWeight.bold)),
                _intField('minRrMs', acceptance.minRrMs, notifier.setMinRrMs),
                _doubleField('consistencyThreshold', acceptance.consistencyThreshold, notifier.setConsistencyThreshold),
                _intField('coldStartBeats', acceptance.coldStartBeats, notifier.setColdStartBeats),
                _intField('medianWindow', acceptance.medianWindow, notifier.setMedianWindow),
                const SizedBox(height: 8),
                const Text(
                  'Applies on the next Start.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Value-keyed re-seed pattern (must carry over unchanged from
  /// `streams_screen.dart`): `key: ValueKey('$label-$value')` bound to the
  /// *provider-derived* value + `initialValue: value.toString()`, so submit
  /// → notifier write → rebuild → new key → new `initialValue` re-seeds the
  /// field to the round-tripped provider value. A plain `initialValue`
  /// without the value-keyed `ValueKey` would show stale text after submit.
  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: ValueKey('$label-$value'),
              initialValue: value.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              onFieldSubmitted: (text) {
                final parsed = int.tryParse(text);
                if (parsed != null) onChanged(parsed);
              },
              onEditingComplete: () => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _doubleField(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: ValueKey('$label-$value'),
              initialValue: value.toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              onFieldSubmitted: (text) {
                final parsed = double.tryParse(text);
                if (parsed != null) onChanged(parsed);
              },
              onEditingComplete: () => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }
}
