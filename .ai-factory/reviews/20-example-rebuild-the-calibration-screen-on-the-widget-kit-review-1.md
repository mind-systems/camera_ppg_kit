# Review: Example — rebuild the Calibration screen on the widget kit

## Scope
Presentation-only recompose of `example/lib/screens/calibration_screen.dart` onto the note-25 widget kit. Reviewed `git diff HEAD`, the full current file, and the widget-kit surfaces it consumes (`widgets.dart` barrel, `section_card.dart`, `state_banner.dart`, `status_chip.dart`, `async_states.dart`, `status_color.dart`). Cross-checked against the sibling rebuild `streams_screen.dart`.

## Verification performed
- `flutter analyze example/lib/screens/calibration_screen.dart` → **No issues found**.
- Grepped for stale references to the renamed/removed helpers (`_countdown`, `_qualityAndStateRow`, `_countedBeatsField`, `_saveSection`) → none remain.
- Confirmed the `import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;` alias resolves the collision with the kit's `AsyncError` (async_states.dart), and the file uses no symbol from riverpod named `AsyncError` — safe hide, mirrors `streams_screen.dart:5`.
- Confirmed every consumed symbol (`SectionCard`, `StateBanner`, `StatusChip`, `AsyncEmpty`, `AsyncError`, `qualityColor`, `idleColor`/`pendingColor`/`goodColor`/`fairColor`) is exported by the `widgets.dart` barrel.
- `const StateBanner('…', fairColor)` — both args are compile-time constants; the const ctor is valid.

## Behavior-preservation check (presentation-only guard)
All note-21 logic is untouched by the diff:
- Recorder wiring (`_recorder.start/stop/save`), the 60 s `_finishTimer`/1 Hz `_tickTimer`, `_finish`/`_stopManually`/`_save`, and `dispose` are unchanged.
- The `service.isMeasuring` gate and the `_blockedByNotMeasuring`/`_recording`/`_recorded`/`_savedPath`/`_windowSeconds` flags and their transitions are unchanged.
- The frame-rate rebuild-isolation pattern is preserved and correctly extended: `_bpmSection`, `_signalCard`, and the new `_stateBanner` each wrap their frame-cadence `ref.watch` in a local `Consumer`, so the countdown/buttons stay driven only by the 1 Hz tick. `_stateLabelColor` covers exactly the four current enum values with no `done` arm (note 23), and the intentional `poorSignal → fairColor` mapping is retained with its explanatory comment.

## Observations (non-blocking, not defects)
- The signal card (`_signalCard`, titled "Signal") renders SQI only, with no finger-presence row — the plan's Task 2 title and ListView ordering call it the "SQI/finger card". This matches the *original* screen (which never displayed finger presence), so it is not a regression; the plan wording is looser than the implementation, not the reverse. No behavioral or correctness impact.

No correctness, security, or runtime concerns found.

REVIEW_PASS
