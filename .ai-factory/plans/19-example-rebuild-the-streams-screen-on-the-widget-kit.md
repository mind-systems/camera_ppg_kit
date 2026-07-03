# Plan: Example: rebuild the Streams screen on the widget kit

## Context
Recompose the pure-consumer Streams screen (`example/lib/screens/streams_screen.dart`) on the note-25 widget kit so it matches neiry's bar — `SectionCard`s, a prominent monospace BPM headline, an artifact-flagged live-RR card, `StatusChip` signal/finger status, a `StateBanner`, and real "waiting for signal…" async states — with the `ref.watch`/`ref.listen` consumer logic (note 22) left byte-for-byte intact.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Rebuild the Streams screen on the widget kit

All work is in the single file `example/lib/screens/streams_screen.dart`. The sibling rebuild `example/lib/screens/source_screen.dart` (note 26) is the exact pattern to follow — reuse its import style, `AsyncValue.when` gating, `StateBanner`/`StatusChip`/`SectionCard`/`AsyncEmpty` usage, and semantic colors from `status_color.dart`. **Preserve unchanged** (note 22, presentation-only): the `_rrHistory` list, the `ref.listen(rrProvider, …)` insert/trim, the `ref.listen(stateProvider, …)` warm-up clear, `ConsumerStatefulWidget`, and all provider reads (`rrProvider`, `bpmProvider`, `qualityProvider`, `fingerPresenceProvider`, `stateProvider`). No start/stop, no camera, no lifecycle. No `done`/"Complete" arm (note 23) — the state switch stays the four current enum values only.

- [x] **Task 1: Wire the widget kit and rebuild the screen scaffold**
  Files: `example/lib/screens/streams_screen.dart`
  Add `import '../widgets/widgets.dart';` and switch the riverpod import to `import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;` (the kit's `AsyncError` in `async_states.dart` collides with riverpod's — mirror `source_screen.dart`). Keep the `_rrHistory` field and both `ref.listen` blocks verbatim. Rebuild `build`'s `ListView` (padding 16) to compose, in order: `StateBanner` (state), then the BPM card (Task 2), the live-RR card (Task 3), and the signal card (Task 4), with `SizedBox(height: 16)` between cards. Replace the inline `_stateBanner` `Container` with a `StateBanner(label, color)` fed by a `_stateLabelColor` switch copied from `source_screen.dart` (`idle→idleColor`, `warmup→pendingColor`+'Hold still… warming up', `measuring→goodColor`+'Measuring', `poorSignal→fairColor`+'Poor signal — check finger placement'); delete the old `_stateBanner` method and its inline color map.

- [x] **Task 2: BPM headline card** (depends on Task 1)
  Files: `example/lib/screens/streams_screen.dart`
  Replace `_bpmSection` with a `SectionCard(title: 'BPM')` whose child is a centered, large monospace number — a big `Text(bpm?.toString() ?? '—', style: TextStyle(fontFamily: 'monospace', fontSize: 56, fontWeight: FontWeight.bold))` (or an equivalent centered `MetricRow` with `mono: true`) — with a small grey "derived, display-only" caption below. Keep reading `ref.watch(bpmProvider)`. This is the headline metric, so keep it visually prominent.

- [x] **Task 3: Live-RR card (latest + rolling list, artifact-flagged, not filtered)** (depends on Task 1)
  Files: `example/lib/screens/streams_screen.dart`
  Replace `_rrSection` with a `SectionCard(title: 'Live RR')`. Gate the latest interval on the `AsyncValue` from `ref.watch(rrProvider)` via `.when`: `loading → AsyncEmpty('waiting for signal…')`, `error → AsyncError(error)`, `data →` show "Latest: `<ms>` ms" with an "(artifact)" flag when `isArtifact`. Below it, render the rolling `_rrHistory` `Wrap` of per-beat chips — reuse `StatusChip('${rr.intervalMs}${rr.isArtifact ? '*' : ''}', rr.isArtifact ? poorColor : goodColor)` so rejected beats are visibly flagged (color, not removed — note 14). Do not filter artifacts out of the list.

- [x] **Task 4: Signal card (SQI + finger-presence StatusChips, async-gated)** (depends on Task 1)
  Files: `example/lib/screens/streams_screen.dart`
  Replace `_qualityAndPresenceRow` with a `SectionCard(title: 'Signal')`. Gate SQI on `ref.watch(qualityProvider)` via `.when` exactly as `source_screen.dart:_signalCard` does: `data → StatusChip('SQI: ${quality.name}', qualityColor(quality))`, `loading → AsyncEmpty('waiting for signal…')`, `error → AsyncError(error)`. Render finger-presence via `ref.watch(fingerPresenceProvider).value` mapped through the existing `present/absent/overBright/null` switch — as a `StatusChip` (or `LabelRow('Finger', …)` matching source-screen). Delete the old inline `Chip` + color logic.
