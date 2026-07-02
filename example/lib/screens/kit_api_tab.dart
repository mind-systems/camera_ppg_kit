import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auto_detect/log.dart';
import '../providers/camera_ppg_service_provider.dart';
import '../providers/stream_providers.dart';

/// Tab 2 — dogfoods the kit's **public barrel only** (spec note 14).
///
/// Imports only `package:camera_ppg_kit/camera_ppg_kit.dart` — no
/// `CameraImage`/`PPGSignal`/`FlutterPPGService`/`CameraController` type
/// appears here. Subscriptions live in the Riverpod providers (Task 3); this
/// widget reads them with `ref.watch`/`ref.listen` and never opens a
/// `StreamBuilder` or a per-widget `.listen()` of its own — a rebuild must
/// never re-subscribe.
///
/// `ConsumerStatefulWidget` rather than a plain `ConsumerWidget` because the
/// camera-override picker and the `[debug]` tuning panel (Task 6) need local
/// UI-only mutable state (selected camera id, form field values, a short RR
/// rolling list) alongside the provider reads — that local state is never a
/// second stream subscription.
class KitApiTab extends ConsumerStatefulWidget {
  const KitApiTab({super.key});

  @override
  ConsumerState<KitApiTab> createState() => _KitApiTabState();
}

class _KitApiTabState extends ConsumerState<KitApiTab> {
  // ── Camera override ───────────────────────────────────────────────────
  List<CameraPpgCameraInfo> _cameras = [];
  String? _selectedCameraId;
  bool _loadingCameras = false;

  // ── Start/stop outcome ────────────────────────────────────────────────
  CameraPpgError? _lastError;

  // ── RR rolling list (display-only, cleared on every new warm-up) ───────
  final List<RrInterval> _rrHistory = [];

  // ── [debug] session-policy knobs (spec note 09) — seeded from the kit's
  // own defaults so this panel never invents numbers that drift from them.
  late int _warmupSeconds;
  late int _targetSeconds;
  late int _silenceSeconds;
  late SignalQuality _sqiFloor;

  // ── [debug] RR-gate knobs (spec note 12) ────────────────────────────────
  late int _minRrMs;
  late double _consistencyThreshold;
  late int _coldStartBeats;
  late int _medianWindow;

  bool _debugExpanded = false;

  @override
  void initState() {
    super.initState();
    final defaultPolicy = SessionPolicy();
    final defaultAcceptance = RrAcceptance();
    _warmupSeconds = defaultPolicy.warmupDuration.inSeconds;
    _targetSeconds = defaultPolicy.targetDuration.inSeconds;
    _silenceSeconds = defaultPolicy.silenceWindow.inSeconds;
    _sqiFloor = defaultPolicy.sqiFloor;
    _minRrMs = defaultAcceptance.minRrMs;
    _consistencyThreshold = defaultAcceptance.consistencyThreshold;
    _coldStartBeats = defaultAcceptance.coldStartBeats;
    _medianWindow = defaultAcceptance.medianWindow;
    // Deferred rather than called directly: `TabBarView` mounts this tab
    // lazily, sometimes during its own layout pass, and `_loadCameras`'s
    // synchronous pre-await `setState()` can trip a "setState() called
    // during build" assertion if it runs inline from `initState` in that
    // window. A post-frame callback runs it once the current build/layout
    // has finished instead (review pass 2, finding 1).
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
      // one item (review pass 2, finding 2).
      if (_selectedCameraId != null && !_cameras.any((c) => c.id == _selectedCameraId)) {
        _selectedCameraId = null;
      }
    });
  }

  void _selectCamera(String? id) {
    ppgTap('kit_camera_override:${id ?? "auto"}');
    setState(() => _selectedCameraId = id);
  }

  SessionPolicy _buildPolicy() => SessionPolicy(
        warmupDuration: Duration(seconds: _warmupSeconds),
        targetDuration: Duration(seconds: _targetSeconds),
        silenceWindow: Duration(seconds: _silenceSeconds),
        sqiFloor: _sqiFloor,
      );

  RrAcceptance _buildAcceptance() => RrAcceptance(
        minRrMs: _minRrMs,
        consistencyThreshold: _consistencyThreshold,
        coldStartBeats: _coldStartBeats,
        medianWindow: _medianWindow,
      );

  Future<void> _start(MeasurementState currentState) async {
    ppgTap('kit_start');
    setState(() => _lastError = null);
    final service = ref.read(cameraPpgServiceProvider);
    if (currentState == MeasurementState.done) {
      // `done` is terminal (spec note 09) and `CameraPpgSession` does not
      // release the camera/torch on its own when it's reached — only
      // stop()/dispose() do. Release the finished session first so Start
      // from `done` recovers instead of hitting the service's re-entry
      // guard as a silent no-op (review finding 1).
      await service.stopMeasurement();
    }
    final error = await service.startMeasurement(
      cameraId: _selectedCameraId,
      policy: _buildPolicy(),
      acceptance: _buildAcceptance(),
    );
    if (!mounted) return;
    setState(() => _lastError = error);
  }

  Future<void> _stop() async {
    ppgTap('kit_stop');
    await ref.read(cameraPpgServiceProvider).stopMeasurement();
  }

  @override
  Widget build(BuildContext context) {
    // Providers, not raw streams — a rebuild here re-reads provider state,
    // it never re-subscribes (the subscription lives in the provider).
    ref.listen<AsyncValue<RrInterval>>(rrProvider, (previous, next) {
      next.whenData((rr) {
        setState(() {
          _rrHistory.insert(0, rr);
          if (_rrHistory.length > 12) _rrHistory.removeLast();
        });
      });
    });
    ref.listen<AsyncValue<MeasurementState>>(stateProvider, (previous, next) {
      // `warmup` is entered exactly once per measurement, right after a
      // sensor locks — clear the rolling list here so it never shows beats
      // from a previous measurement.
      next.whenData((s) {
        if (s == MeasurementState.warmup) {
          setState(() => _rrHistory.clear());
        }
      });
    });

    final stateAsync = ref.watch(stateProvider);
    final state = stateAsync.value ?? MeasurementState.idle;
    // `isRunning` covers only the states where a live measurement is
    // in flight — `done` is terminal but still holds an open (unreleased)
    // session, so it must not be lumped in with `idle` (review finding 1):
    // Stop needs to stay enabled to release it, and Start needs to route
    // through the `done`-recovery path in `_start` rather than being
    // enabled straight into the service's re-entry no-op.
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
          _startStopRow(state: state, isRunning: isRunning, canStop: canStop),
          const SizedBox(height: 16),
          _qualityAndPresenceRow(),
          const SizedBox(height: 16),
          _bpmSection(),
          const SizedBox(height: 16),
          _rrSection(),
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
      MeasurementState.done => ('Complete', Colors.indigo),
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
              ppgTap('kit_retry');
              // A failed start() always leaves the session at `idle` (spec
              // note 07) — retry never needs the `done`-recovery path.
              _start(MeasurementState.idle);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _startStopRow({
    required MeasurementState state,
    required bool isRunning,
    required bool canStop,
  }) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: isRunning ? null : () => _start(state),
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

  Widget _bpmSection() {
    final bpm = ref.watch(bpmProvider);
    return Center(
      child: Column(
        children: [
          Text(
            bpm?.toString() ?? '—',
            style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
          ),
          const Text('BPM (derived, display-only)', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _rrSection() {
    final latest = ref.watch(rrProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Latest RR: ${latest != null ? '${latest.intervalMs} ms${latest.isArtifact ? ' (artifact)' : ''}' : '—'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final rr in _rrHistory)
              Chip(
                label: Text('${rr.intervalMs}${rr.isArtifact ? '*' : ''}'),
                backgroundColor: rr.isArtifact ? Colors.red.shade50 : Colors.green.shade50,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: rr.isArtifact ? Colors.red : Colors.green.shade800,
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
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
                        ppgTap('kit_refresh_cameras');
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
                _intField('Warm-up (s)', _warmupSeconds, (v) => setState(() => _warmupSeconds = v)),
                _intField('Target duration (s)', _targetSeconds, (v) => setState(() => _targetSeconds = v)),
                _intField('Silence window (s)', _silenceSeconds, (v) => setState(() => _silenceSeconds = v)),
                Row(
                  children: [
                    const Text('SQI floor:'),
                    const SizedBox(width: 8),
                    DropdownButton<SignalQuality>(
                      value: _sqiFloor,
                      items: [
                        for (final q in SignalQuality.values)
                          DropdownMenuItem(value: q, child: Text(q.name)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _sqiFloor = v);
                      },
                    ),
                  ],
                ),
                const Divider(),
                const Text('RR-gate (note 12)', style: TextStyle(fontWeight: FontWeight.bold)),
                _intField('minRrMs', _minRrMs, (v) => setState(() => _minRrMs = v)),
                _doubleField('consistencyThreshold', _consistencyThreshold,
                    (v) => setState(() => _consistencyThreshold = v)),
                _intField('coldStartBeats', _coldStartBeats, (v) => setState(() => _coldStartBeats = v)),
                _intField('medianWindow', _medianWindow, (v) => setState(() => _medianWindow = v)),
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
