// De-halving offline design harness (plan 23 / spec note 29) — plain-Dart
// fixture loader. NOT part of the kit's public surface; lives under `test/`
// only. Depends on `dart:io`/`dart:convert` plus the kit's pure `RrInterval`
// value type — no Flutter/camera imports.
import 'dart:convert';
import 'dart:io';

import 'package:camera_ppg_kit/camera_ppg_kit.dart';

/// One row of `.calibration/*.json`'s `intervals[]` — a single emission from
/// `flutter_ppg`'s rolling-RR stream (NOT one row per beat; see plan 23's
/// Reference facts).
class FixtureBeat {
  const FixtureBeat({
    required this.tMs,
    required this.rrMs,
    required this.isArtifact,
    required this.sqi,
  });

  factory FixtureBeat.fromJson(Map<String, dynamic> json) => FixtureBeat(
        tMs: json['tMs'] as int,
        rrMs: json['rrMs'] as int,
        isArtifact: json['isArtifact'] as bool,
        sqi: json['sqi'] as String,
      );

  /// Device-clock milliseconds of the emission (not a beat index).
  final int tMs;

  /// RR interval magnitude in milliseconds.
  final int rrMs;

  /// Whether `rr_acceptance.dart` (as recorded on-device) flagged this row.
  final bool isArtifact;

  /// Signal-quality label at the time of emission (e.g. `"good"`).
  final String sqi;
}

/// The `acceptance` block recorded in the fixture header — the exact
/// `RrAcceptance` params the on-device run used.
class FixtureAcceptanceParams {
  const FixtureAcceptanceParams({
    required this.minRrMs,
    required this.consistencyThreshold,
    required this.coldStartBeats,
    required this.medianWindow,
  });

  factory FixtureAcceptanceParams.fromJson(Map<String, dynamic> json) =>
      FixtureAcceptanceParams(
        minRrMs: json['minRrMs'] as int,
        consistencyThreshold: (json['consistencyThreshold'] as num)
            .toDouble(),
        coldStartBeats: json['coldStartBeats'] as int,
        medianWindow: json['medianWindow'] as int,
      );

  final int minRrMs;
  final double consistencyThreshold;
  final int coldStartBeats;
  final int medianWindow;
}

/// The `policy` block recorded in the fixture header — the session-lifecycle
/// (warm-up/silence/quality-floor) params the on-device run used. Not
/// consumed by the acceptance-gate replay itself, but grounds how far into
/// the stream a pre-recording warm-up phase (see Task 3's fixture-2 finding)
/// could plausibly reach.
class FixturePolicy {
  const FixturePolicy({
    required this.warmupMs,
    required this.silenceMs,
    required this.sqiFloor,
  });

  factory FixturePolicy.fromJson(Map<String, dynamic> json) => FixturePolicy(
        warmupMs: json['warmupMs'] as int,
        silenceMs: json['silenceMs'] as int,
        sqiFloor: json['sqiFloor'] as String,
      );

  final int warmupMs;
  final int silenceMs;
  final String sqiFloor;
}

/// The manual beat count taken alongside the run — the ground-truth oracle.
class FixtureManualCount {
  const FixtureManualCount({required this.beats, required this.windowSeconds});

  factory FixtureManualCount.fromJson(Map<String, dynamic> json) =>
      FixtureManualCount(
        beats: json['beats'] as int,
        windowSeconds: json['windowSeconds'] as int,
      );

  final int beats;
  final int windowSeconds;
}

/// The on-device summary recorded at capture time — used by Task 3 to
/// confirm the harness reproduces the recorded run before any candidate is
/// judged.
class FixtureSummary {
  const FixtureSummary({
    required this.totalIntervals,
    required this.acceptedIntervals,
    required this.artifactIntervals,
    required this.meanAcceptedRrMs,
    required this.kitBpm,
  });

  factory FixtureSummary.fromJson(Map<String, dynamic> json) => FixtureSummary(
        totalIntervals: json['totalIntervals'] as int,
        acceptedIntervals: json['acceptedIntervals'] as int,
        artifactIntervals: json['artifactIntervals'] as int,
        meanAcceptedRrMs: (json['meanAcceptedRrMs'] as num).toDouble(),
        kitBpm: json['kitBpm'] as int,
      );

  final int totalIntervals;
  final int acceptedIntervals;
  final int artifactIntervals;
  final double meanAcceptedRrMs;
  final int kitBpm;
}

/// A parsed `.calibration/*.json` capture: header + the raw `intervals[]`
/// stream. Rate-scoring metrics (BPM, error, cluster classification) live in
/// `scoring.dart`, not here — this type only parses and exposes the fixture.
class CalibrationFixture {
  const CalibrationFixture({
    required this.name,
    required this.schemaVersion,
    required this.durationMs,
    required this.acceptance,
    required this.policy,
    required this.manualCount,
    required this.summary,
    required this.intervals,
  });

  factory CalibrationFixture.fromJson(String name, Map<String, dynamic> json) {
    return CalibrationFixture(
      name: name,
      schemaVersion: json['schemaVersion'] as int,
      durationMs: json['durationMs'] as int,
      acceptance:
          FixtureAcceptanceParams.fromJson(
              json['acceptance'] as Map<String, dynamic>),
      policy: FixturePolicy.fromJson(json['policy'] as Map<String, dynamic>),
      manualCount: FixtureManualCount.fromJson(
          json['manualCount'] as Map<String, dynamic>),
      summary:
          FixtureSummary.fromJson(json['summary'] as Map<String, dynamic>),
      intervals: (json['intervals'] as List<dynamic>)
          .map((e) => FixtureBeat.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// Fixture file name (without directory), for labeling harness output.
  final String name;

  final int schemaVersion;

  /// Wall-clock capture duration (ms) — NOT used for rate scoring (plan 23:
  /// "never mix in the file's `durationMs`"). Kept only for header fidelity.
  final int durationMs;

  final FixtureAcceptanceParams acceptance;
  final FixturePolicy policy;
  final FixtureManualCount manualCount;
  final FixtureSummary summary;
  final List<FixtureBeat> intervals;

  /// Reference BPM derived from the manual count over its own window —
  /// `manualCount.beats / manualCount.windowSeconds * 60`. This is the
  /// oracle every candidate's derived BPM is scored against.
  double get referenceBpm => manualCount.beats / manualCount.windowSeconds * 60;

  /// Maps each raw [FixtureBeat] to a kit [RrInterval], synthesizing a
  /// [DateTime] timestamp from [FixtureBeat.tMs] since [RrInterval.timestamp]
  /// is required but the gate/candidates under test only read [RrInterval.intervalMs].
  List<RrInterval> toRrIntervals() => intervals
      .map((b) => RrInterval(
            intervalMs: b.rrMs,
            timestamp: DateTime.fromMillisecondsSinceEpoch(b.tMs),
            isArtifact: b.isArtifact,
          ))
      .toList(growable: false);
}

/// Loads both calibration fixtures bundled under `test/dehalving/fixtures/`.
///
/// The path is resolved relative to the package root via [Directory.current]
/// — under `flutter test`, the working directory is the package root — never
/// via `Platform.script`, which breaks when the harness is invoked from a
/// subdirectory.
List<CalibrationFixture> loadAll() {
  const names = [
    'calib_20260703_161520.json',
    'calib_20260703_163042.json',
  ];
  final dir = Directory.current.path;
  return names.map((name) {
    final file = File('$dir/test/dehalving/fixtures/$name');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return CalibrationFixture.fromJson(name, json);
  }).toList(growable: false);
}
