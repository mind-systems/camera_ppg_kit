# Code Review — Example: rebuild the Source screen on the widget kit

**Plan:** `.ai-factory/plans/18-example-rebuild-the-source-screen-on-the-widget-kit.md`
**Spec:** `.ai-factory/notes/26-source-screen-rebuild.md` (notes 22, 23, 25)
**Code changed:** `example/lib/screens/source_screen.dart` (only file with runtime changes; the rest of the diff is the plan/plan-review artifacts)
**Risk:** 🟢 Low — presentation-only recomposition onto the note-25 widget kit.

## Scope check
The diff touches exactly one runtime file, `source_screen.dart`, and only its presentation. All behavioural invariants named by the spec are preserved:
- Sole Start/Stop control (`_start`/`_stop`), permission flow (`_checkAndRequestCameraPermission`), camera-override load/select logic, and `sessionConfigProvider` reads/writes are unchanged.
- Every `ppgTap(...)` interaction log is retained (start, stop, retry, camera override, refresh, permission request/open-settings).
- The value-keyed `ValueKey('$label-$value')` re-seed pattern on the tuning fields is intact.
- Kit `lib/`, the recorder (note 20), and the service (note 16) are untouched.

## Verification performed
- **Widget-kit signatures match usage.** Confirmed against `example/lib/widgets/`: `StateBanner(String, Color)`, `StatusChip(String, Color)`, `AsyncEmpty(String)`, `AsyncError(Object)`, `LabelRow(String, String)`, `SectionCard({title, subtitle?, child})`, and `qualityColor(SignalQuality?)` / semantic constants (`idleColor`/`pendingColor`/`goodColor`/`fairColor`/`poorColor`). All calls conform.
- **`AsyncError` name collision handled.** `flutter_riverpod` exports its own `AsyncError`; the widget barrel exports `async_states.dart`'s `AsyncError`. The import `... hide AsyncError` correctly resolves the ambiguity in favour of the kit's, with an explanatory comment. No other riverpod symbol is shadowed, and riverpod's `AsyncError` is not used anywhere in the file.
- **Async-state mapping is correct.** `qualityProvider` is a `StreamProvider<SignalQuality>` (non-null data type) that sits in `loading` until first emit — there is no null-data state pre-signal. `_signalCard` maps `loading → AsyncEmpty('waiting for signal…')`, `data → StatusChip`, `error → AsyncError`, satisfying the Verify line ("waiting… before signal arrives") rather than surfacing a bare spinner. In the `data` branch `quality` is non-null, so `quality.name` / `qualityColor(quality)` are safe.
- **Finger-presence read preserved.** Still `ref.watch(fingerPresenceProvider).value` with the existing `null → 'unknown'` fallback via the `presenceLabel` switch; rendered as a `LabelRow`. No spinner, matching the plan's deliberate decision.
- **State→(label,color) mapping.** `_stateLabelColor` enumerates exactly the four live enum values (idle/warmup/measuring/poorSignal) with the original labels and current colors; no `MeasurementState.done`/"Complete" arm reintroduced (note 23). The `poorSignal → fairColor` (orange, not `poorColor`/red) choice is preserved and documented as intentional.
- **Doubled `[debug]` header avoided.** `SectionCard(title: '[debug] tuning')` is the sole header; the inner `ExpansionTile` title is the neutral `Text('Tuning knobs')`, so the string is not rendered twice (plan-review issue 1 resolved).
- **Error banner.** Rebuilt on `StateBanner(..., poorColor)` carrying `type.name` + optional `message` + permanently-denied guidance line, followed by a full-width Retry `OutlinedButton` (with its `ppgTap('source_retry')` + `_start()`), gated on `_lastError != null` in `build`. Fields used (`error.type.name`, `error.message`, `error.permanentlyDenied`) are the same ones the pre-refactor code used.
- **No dangling references.** The removed helper names (`_stateBanner`, `_startStopRow`, `_qualityAndPresenceRow`, `_cameraOverrideSection`) do not appear in `source_screen.dart`; `build` calls only the defined helpers (`_stateLabelColor`, `_errorBanner`, `_controlCard`, `_signalCard`, `_cameraOverrideCard`, `_debugPanel`). Remaining occurrences of those old names elsewhere are doc comments in the widget kit and the not-yet-rebuilt `streams_screen.dart` (note 27, out of scope).

## Runtime-safety notes
- No layout crash risk: `AsyncEmpty`/`AsyncError` are `Center`-based widgets placed inside the card's `Column` (bounded width via the `ListView`/`Card`, unbounded height → shrink-to-child); no unbounded-constraint overflow.
- No null-deref, type mismatch, or state-machine regression introduced. No migrations, isolates, or channel changes involved.

No findings.

REVIEW_PASS
