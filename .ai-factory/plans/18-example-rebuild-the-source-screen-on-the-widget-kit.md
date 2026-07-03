# Plan: Example — rebuild the Source screen on the widget kit

## Context
Recompose `example/lib/screens/source_screen.dart` onto the note-25 shared widget kit (`SectionCard`, `StateBanner`, `StatusChip`, `LabelRow`, async-state helpers, `status_color`), replacing its raw `Container`/`Chip`/`ExpansionTile`/inline-color surface with neiry-style cards. Presentation only — Start/Stop, permission, camera-override, and `sessionConfigProvider` tuning behavior stay exactly as they are (note 22), and no `MeasurementState.done` arm is reintroduced (note 23).

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Rebuild the Source screen on the kit

- [x] **Task 1: Import the widget kit and map state → (label, color)**
  Files: `example/lib/screens/source_screen.dart`
  Add `import '../widgets/widgets.dart';` (barrel exporting `SectionCard`, `StateBanner`, `StatusChip`, `MetricRow`/`LabelRow`, async states, `status_color`). Keep every existing import and all provider/service wiring. Introduce a private `MeasurementState → (String label, Color color)` mapping (either a local helper or an inline `switch`) reusing the semantic constants from `status_color.dart` — `idleColor` for idle, `pendingColor` for warmup, `goodColor` for measuring, `fairColor` for poorSignal — carrying the existing labels ("Idle", "Hold still… warming up", "Measuring", "Poor signal — check finger placement"). Only the four current enum values; do **not** add a `done`/"Complete" arm (note 23). This mapping replaces the `(label, color)` switch currently inlined in `_stateBanner`. Add a one-line comment that `poorSignal → fairColor` (orange) is intentional — `poorColor`/red is reserved for the error banner — so a later edit does not "correct" it to `poorColor`.

- [x] **Task 2: State banner + error banner via the shared components** (depends on Task 1)
  Files: `example/lib/screens/source_screen.dart`
  Replace `_stateBanner`'s hand-rolled `Container`/`BoxDecoration` with `StateBanner(label, color)` fed by the Task-1 mapping. Rebuild `_errorBanner` to reuse the shared error style: render the error text (`'${error.type.name}${message}'` plus the permanently-denied guidance line when `error.permanentlyDenied`) through `StateBanner(..., poorColor)`, followed by the existing full-width "Retry" `OutlinedButton` that calls `_start()` (keep its `ppgTap('source_retry')`). Preserve the `_lastError != null` gating in `build`. No change to `_lastError` lifecycle or `_start`/permission logic.

- [x] **Task 3: Control card and Signal card** (depends on Task 2)
  Files: `example/lib/screens/source_screen.dart`
  Wrap Start/Stop in a `SectionCard(title: 'Control', ...)`. Make both buttons full-width semantic buttons: `Start` an `ElevatedButton` (disabled while `isRunning`), `Stop` an `OutlinedButton` (disabled while `!canStop`), each in an `Expanded` inside a `Row` (or stacked full-width) — keep the exact `isRunning`/`canStop` predicates already computed in `build` and the `_start()`/`_stop()` handlers with their `ppgTap` calls.
  Rebuild `_qualityAndPresenceRow` as a `SectionCard(title: 'Signal', ...)`: SQI via `StatusChip('SQI: <name>', qualityColor(quality))` and finger-presence via `LabelRow('Finger', presenceLabel)` (reuse the existing `presenceLabel` switch, including its `null → 'unknown'` fallback). Wrap the SQI read in async states so pre-signal shows a waiting state instead of a blank chip. Note: `qualityProvider`/`fingerPresenceProvider` are `StreamProvider`s that sit in the **`loading`** state (not a null-data state) until their first emit, so a plain `.when(data/loading/error)` would render `AsyncLoader` (a spinner), not the required copy. Map deliberately: gate the SQI `StatusChip` on `quality` and render **`AsyncEmpty('waiting for signal…')` for the pre-signal `loading` case** (satisfying the Verify line), the `StatusChip` once data flows, and `AsyncError` on error. Finger-presence stays a `LabelRow` reusing the existing `null → 'unknown'` fallback (no separate spinner needed for it). Behavior/data source unchanged — presentation only.

- [x] **Task 4: Camera-override card and [debug] tuning card, recompose `build`** (depends on Task 3)
  Files: `example/lib/screens/source_screen.dart`
  Wrap `_cameraOverrideSection` in a `SectionCard(title: 'Camera override', ...)`: keep the `DropdownButton`, the Refresh `TextButton`/loading spinner, `_loadCameras`/`_selectCamera` logic and all `ppgTap` calls exactly as-is (the header text moves into the card title).
  Recompose `_debugPanel` as a `SectionCard(title: '[debug] tuning', ...)` whose child is the existing `ExpansionTile` (an `ExpansionTile` inside the card is acceptable per spec) holding the unchanged `sessionConfigProvider` knobs — `_intField`/`_doubleField` (with their value-keyed `ValueKey` re-seed pattern), the SQI-floor dropdown, and the "Applies on the next Start." hint. Do not touch `sessionConfigProvider` reads/writes. **Avoid the doubled header:** `SectionCard` renders `title` as a bold header and the inner `ExpansionTile` also has `title: Text('[debug] tuning')` — keep `SectionCard(title: '[debug] tuning')` as the sole header and change the inner `ExpansionTile`'s title to a neutral collapse control (e.g. `Text('Tuning knobs')`), so the string is not shown twice.
  Recompose `build`'s `ListView` to render, in order: `StateBanner` (state), the error banner (when `_lastError != null`), Control card, Signal card, Camera-override card, `[debug]` tuning card — using consistent `SizedBox` spacing (align with the kit's card rhythm). Delete any now-dead inline helpers/imports left over from the old surface. Verify the file compiles cleanly with no lifecycle/provider changes.

## Verify
- Source screen reads as neiry-style `SectionCard`s with a `StateBanner` header.
- Start/Stop (with correct disabled states), camera override + Refresh, and `[debug]` tuning still work and still write through `sessionConfigProvider`.
- SQI/finger show a "waiting…" async state before signal arrives, then the `StatusChip`/`LabelRow` once data flows.
- No `MeasurementState.done`/"Complete" arm; kit `lib/`, the recorder (note 20), and the service (note 16) untouched.
