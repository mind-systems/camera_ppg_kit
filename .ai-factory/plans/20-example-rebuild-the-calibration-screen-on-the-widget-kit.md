# Plan: Example — rebuild the Calibration screen on the widget kit

## Context
Recompose `example/lib/screens/calibration_screen.dart` onto the note-25 widget kit (`SectionCard`, `StateBanner`, `StatusChip`, async-state helpers, `status_color`) so it matches the Source/Streams bar. Presentation only — the recorder, countdown timers, `service.isMeasuring` gate, and all `_recording`/`_recorded`/`_savedPath` logic (note 21) keep their exact behavior.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Recompose on the widget kit

- [x] **Task 1: Wire imports and card the countdown + BPM**
  Files: `example/lib/screens/calibration_screen.dart`
  Add `import '../widgets/widgets.dart';` and switch the riverpod import to `import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;` (the kit's `AsyncError` collides with riverpod's — same pattern as `streams_screen.dart:5`). Keep all existing imports (`camera_ppg_kit`, `log`, `calibration_recorder`, the three providers). Wrap the countdown in a `SectionCard(title: 'Countdown', ...)` whose child is the centered `$m:$s` text restyled to `fontFamily: 'monospace', fontSize: 64, fontWeight: FontWeight.bold` (large monospace `1:00 → 0:00`). Convert `_bpmSection()` to a `SectionCard(title: 'BPM', ...)` mirroring `streams_screen.dart:_bpmCard` (monospace 56, grey "derived, display-only" caption) — keep it wrapped in its own `Consumer` so the frame-rate `bpmProvider` watch stays confined to this leaf (the note-21 rebuild-isolation rationale in the existing doc comment must be preserved).

- [x] **Task 2: State banner + SQI/finger via the widget kit** (depends on Task 1)
  Files: `example/lib/screens/calibration_screen.dart`
  Replace the ad-hoc `_qualityAndStateRow()` Chips/inline-color switch with the note-25 widgets, keeping it inside its own `Consumer` (frame-rate `qualityProvider`/`stateProvider` watches must stay off the countdown/buttons — preserve the existing doc-comment rationale). Render the `MeasurementState` as a full-width `StateBanner(label, color)` at the top of the list, resolving label+color with a local `_stateLabelColor` switch over the four current enum values (idle/warmup/measuring/poorSignal — no `done` arm, note 23), copied from `streams_screen.dart:_stateLabelColor` (`poorSignal → fairColor` is intentional). Render SQI as `StatusChip('SQI: ${quality.name}', qualityColor(quality))` using `status_color.dart`'s `qualityColor`, gated on the `qualityProvider` `AsyncValue` (`loading → AsyncEmpty('waiting for signal…')`, `error → AsyncError`), matching `streams_screen.dart:_signalCard`.

- [x] **Task 3: Precondition guidance state + record controls** (depends on Task 2)
  Files: `example/lib/screens/calibration_screen.dart`
  Replace the hand-rolled orange `_guidanceBanner()` `Container` with the widget kit: when `_blockedByNotMeasuring` show a `StateBanner('Start measurement on the Source screen first', fairColor)` (or an `AsyncEmpty` guidance card) — a proper, explained guidance state, not a silently disabled button. Keep the `_blockedByNotMeasuring` flag and its set in `_startRecording()` exactly as-is. Convert `_recordButtonsRow()` to full-width semantic buttons with obvious disabled state: a full-width `ElevatedButton` ("Start recording", disabled while `_recording`) and a full-width `OutlinedButton` ("Stop", enabled only while `_recording`) — keep the `Row`+`Expanded` layout and the existing `onPressed` wiring (`_startRecording`/`_stopManually`) untouched.

- [x] **Task 4: Save card** (depends on Task 3)
  Files: `example/lib/screens/calibration_screen.dart`
  Move the counted-beats `TextField` (`_countedBeatsField`), the Save `ElevatedButton` (enabled on `_recorded`, wired to `_save`), and the saved-path display into a single `SectionCard(title: 'Save', ...)`. Render the written path as `SelectableText(_savedPath!)` below the Save button, shown only when `_savedPath != null` (behavior identical to the current `_saveSection`). Reassemble the top-level `ListView` so the ordering reads: `StateBanner` → countdown card → record controls (+ guidance state when blocked) → BPM card → SQI/finger card → save card, with the existing 16 px spacing rhythm. Do not touch `_recorder`, the timers, `_finish`/`_stopManually`/`_save`, or `dispose` — presentation only.
