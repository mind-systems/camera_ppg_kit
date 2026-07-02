# Architecture: Structured Modules (Technical Layers)

## Overview

`camera_ppg_kit` is a small, single-purpose Flutter plugin — a facade that wraps the `flutter_ppg` and `camera` packages (plus native camera-selection bridges) behind an idiomatic Dart API. Its architecture is **Structured Modules organized by technical layer**: a public API barrel re-exports a `lib/src/` tree whose folders are split by role (`api`, `models`, `channel`, `processing`, `util`), with native platform code isolated in `android/` and `ios/`. This is the lightest pattern that still enforces a hard public boundary and keeps signal-processing concerns separate from the API surface — and it mirrors the proven layout of the sibling `neiry_kit`.

The kit is deliberately not service/controller-centric (there is no server, no HTTP, no persistence). The "domain" is thin: value types for RR intervals and signal quality, plus a measurement-session lifecycle. The structure exists to keep the wrapped third-party packages and the native channel hidden, so the consumer (`mind_mobile`) depends only on a stable Dart surface.

## Decision Rationale

- **Project type:** standalone Flutter plugin ("kit") acting as one biometric source among several
- **Tech stack:** Dart (plugin); selection + enumeration are Dart-side via the `camera` plugin, so native Kotlin/Swift is at most a torch fallback (deletion candidate); `flutter_ppg`, `camera`
- **Key factor:** small surface, single deployment, low domain complexity, but a **hard public boundary** is required so the host never couples to `flutter_ppg`/`camera`/native details. Structured Modules (technical layers) gives that boundary without the overhead of Explicit Architecture, and matches `neiry_kit` for cross-kit consistency.

## Folder Structure

```
camera_ppg_kit/
├── lib/
│   ├── camera_ppg_kit.dart                  # PUBLIC BARREL — the only import surface for consumers
│   ├── camera_ppg_kit_platform_interface.dart
│   ├── camera_ppg_kit_method_channel.dart   # default platform-channel implementation
│   └── src/                                 # ── INTERNAL — never imported directly by consumers ──
│       ├── api/                             # high-level Dart surface (measurement session, streams, camera override)
│       ├── models/                          # value types crossing the API boundary
│       │   ├── rr_interval.dart             # RR interval (ms) — kept compatible with neiry_kit's type
│       │   ├── signal_quality.dart          # Good / Fair / Poor + SNR
│       │   ├── measurement_state.dart       # session lifecycle / finger-presence
│       │   └── camera_ppg_error.dart        # typed error/state values (no throwing across the channel)
│       ├── channel/                         # method/event-channel names + shared enums
│       ├── processing/                      # acceptance / outlier policy layered on flutter_ppg (cf. neiry's ppg_peak_detector)
│       └── util/                            # internal logging helper (cf. neiry's nlog.dart)
├── android/                                 # Kotlin plugin — torch fallback only if needed (deletion candidate)
├── ios/                                     # Swift plugin — torch fallback only if needed (deletion candidate)
├── example/                                 # standalone app — validate end-to-end on real hardware
└── test/                                    # plugin unit tests
```

## Dependency Rules

- ✅ `camera_ppg_kit.dart` (barrel) → re-exports from `lib/src/` only. **Deliberate exception:** `src/processing/session_policy.dart` (`SessionPolicy`) and `src/processing/rr_acceptance.dart` (`RrAcceptance`) are re-exported too — spec note 19 names them `[debug]`-tagged extras that are *present in the public API but not part of the consumer contract*, needed so the example's plain-Dart `CameraPpgService` (kit-barrel-only imports) can construct tuned instances for `CameraPpgSession`'s optional `policy`/`acceptance` ctor params. `mind_mobile` always omits them. The rest of `src/processing/` (and all of `src/channel/`, `src/util/`) stays unexported.
- ✅ `src/api/` → depends on `src/models/`, `src/channel/`, `src/processing/`, `src/util/`, and on `flutter_ppg` / `camera`.
- ✅ `src/processing/` → depends on `src/models/` only (pure Dart signal/acceptance logic; no `camera`/channel imports). **Deliberate sole exception:** `src/processing/frame_isolate.dart` imports `camera` + `flutter_ppg` — it is the isolate-boundary host (spawns the long-lived background isolate, runs `FlutterPPGService` inside it, adapts `CameraImage` <-> the sendable `FrameMessage`/`SignalMessage` types in `frame_message.dart`), not general signal/acceptance logic. `frame_message.dart` itself stays pure (`dart:typed_data` + `dart:isolate` only). The `CameraController` wiring stays in `src/api/` per spec note 13.
- ✅ `src/models/` → pure value types; depend on nothing else in the kit.
- ✅ Native (`android/`, `ios/`) → communicate with Dart **only** through the names declared in `src/channel/`.
- ❌ Consumers (incl. `mind_mobile`) importing anything under `lib/src/` directly — they use the barrel only.
- ❌ Any kit file importing from `mind_mobile` or the app logger facade.
- ❌ `flutter_ppg` / `camera` / `MethodChannel` types leaking out through the public API — wrap them in `src/models/` types first.
- ❌ Throwing across the platform-channel boundary for expected states — return typed `models/` values instead.

## Layer/Module Communication

- **Native → Dart:** event channels stream camera-selection results and (where native does the work) raw frame metadata; method channels handle start/stop and torch control. All channel names live in `src/channel/`.
- **flutter_ppg → kit:** the `camera` plugin's frame stream feeds `flutter_ppg`, whose `PPGSignal` output is adapted by `src/processing/` and `src/api/` into the kit's own `RrInterval` / `SignalQuality` models.
- **kit → consumer:** the `api/` layer exposes broadcast `Stream`s (RR intervals, quality/state) plus session-control methods. Consumers subscribe; nothing pushes app-domain types inward.
- **Boundary conversion:** third-party and channel types are converted to `models/` types at the `api/`/`processing/` edge — the same domain→DTO discipline `neiry_kit` uses, so both sources feed `mind_mobile`'s RR contract identically.

## Key Principles

1. **The barrel is the contract.** Everything consumers may use is re-exported from `camera_ppg_kit.dart`; `lib/src/` is private. Adding to the public surface is a deliberate act.
2. **Thin domain, explicit values.** RR interval and signal quality are first-class value types; "not yet available" uses sentinels, matching `neiry_kit` conventions.
3. **No exceptions across the channel.** Permission-denied, no-finger, poor-signal, and unsupported-device are typed states, not thrown errors.
4. **Processing is pure and isolate-friendly.** `src/processing/` holds no Flutter/channel/`camera` imports, so the heavy path can run off the UI work and be unit-tested directly.
5. **Self-contained.** No dependency on `mind_mobile` or its logger; the kit is validated through its own `example/` app before integration.

## Code Examples

### Public barrel re-exports `src/` (the boundary)

```dart
// lib/camera_ppg_kit.dart
export 'src/api/camera_ppg_session.dart';
export 'src/models/rr_interval.dart';
export 'src/models/signal_quality.dart';
export 'src/models/measurement_state.dart';
export 'src/models/camera_ppg_error.dart';
// src/channel, src/processing, src/util are NOT exported — internal only.
```

### API layer wraps third-party types into kit models

```dart
// lib/src/api/camera_ppg_session.dart
import 'package:flutter_ppg/flutter_ppg.dart';
import '../models/rr_interval.dart';
import '../models/signal_quality.dart';

class CameraPpgSession {
  final _rr = StreamController<RrInterval>.broadcast();
  Stream<RrInterval> get rrStream => _rr.stream;   // consumer sees only kit models

  void _onSignal(PpgSignal signal) {               // flutter_ppg type stays inside
    for (final ms in signal.rrIntervalsMs) {
      _rr.add(RrInterval(milliseconds: ms, quality: SignalQuality.fromSnr(signal.snr)));
    }
  }
}
```

### Pure processing layer (no Flutter/channel imports — unit-testable, isolate-safe)

```dart
// lib/src/processing/rr_acceptance.dart
import '../models/rr_interval.dart';

/// Rejects physiologically implausible intervals before they reach consumers.
bool isAcceptable(RrInterval rr) =>
    rr.milliseconds >= 300 && rr.milliseconds <= 2000;
```

## Anti-Patterns

- ❌ Importing `package:camera_ppg_kit/src/...` from `mind_mobile` — bypasses the public contract.
- ❌ Returning a `flutter_ppg` `PpgSignal` or a `MethodChannel` map from a public API method.
- ❌ Putting `camera`/channel calls inside `src/processing/` — it must stay pure so it can run in an isolate and be tested without hardware.
- ❌ Throwing across the platform channel for a normal "no finger detected" condition instead of emitting a typed state.
- ❌ Computing BPM/HRV inside the kit — the kit emits RR + quality; the consumer derives higher-level metrics.
- ❌ Depending on `mind_mobile` or its logger facade from any kit file.
