# Plan: Rename the Kit-API consumer screen → "Streams"

## Context
After note 22 stripped the "Kit API" tab to a pure `ref.watch` consumer, its name is misleading — it only displays live streams. Rename the tab label to "Streams" and the file/class to match neiry's parity (`kit_api_tab.dart`/`KitApiTab` → `streams_screen.dart`/`StreamsScreen`), with no behavior change.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Rename

- [x] **Task 1: Rename the file and class**
  Files: `example/lib/screens/kit_api_tab.dart` → `example/lib/screens/streams_screen.dart`
  Move `kit_api_tab.dart` to `streams_screen.dart` (`git mv` to preserve history). Rename the public class `KitApiTab` → `StreamsScreen` and its state class `_KitApiTabState` → `_StreamsScreenState` (including the `createState()` return). Update the leading doc comment so it reads as the "Streams" consumer screen instead of the "Kit-API branch" — keep the substance (pure display consumer per note 22, barrel-only, `ref.watch`, UI-only rolling list). Do NOT touch what the screen watches or displays — pure rename.

- [x] **Task 2: Update the shell wiring in `main.dart`** (depends on Task 1)
  Files: `example/lib/main.dart`
  Update the import from `screens/kit_api_tab.dart` to `screens/streams_screen.dart`. Rename the `_Branch.kitApi('Kit API')` enum case to `_Branch.streams('Streams')` and update its reference in `_screenFor` (`_Branch.kitApi => const KitApiTab()` → `_Branch.streams => const StreamsScreen()`). Adjust the `_Shell` doc comment mention of the "Kit API" branch to "Streams". The enum ordering (source, streams, calibration, raw) and the Raw-exclusivity hook keyed on `_Branch.raw` stay unchanged.

- [x] **Task 3: Sweep for stale references** (depends on Task 2)
  Files: `example/lib/screens/source_screen.dart` (comments only)
  Run `grep -rn 'KitApiTab\|kit_api_tab\|kitApi' example/lib` and confirm no stale identifiers remain in code. `source_screen.dart` has doc comments referencing `kit_api_tab.dart` (lines ~18, ~48, ~373) — update those textual references to `streams_screen.dart` for consistency. Verify the app builds (`flutter analyze`) and the tab reads "Streams".
