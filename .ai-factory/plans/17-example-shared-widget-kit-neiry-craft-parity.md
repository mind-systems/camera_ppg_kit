# Plan: Example — shared widget kit (neiry-craft parity)

## Context
Extract the repeated inline UI patterns from the example screens (state banner, SQI/status chip, section columns, metric rows, async fallbacks) into a small dependency-free `example/lib/widgets/` kit, so notes 26–28 can rebuild the Source/Streams/Calibration screens on a consistent, neiry-parity surface. Foundation only — no screen is rewired here and the kit's `lib/` is untouched.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Notes for the implementer
- **Scope is `example/lib/widgets/` only.** Do NOT edit `source_screen.dart`, `streams_screen.dart`, `calibration_screen.dart`, `main.dart`, providers, services, or anything under the kit's `lib/`. The screen rebuilds that consume these widgets are separate milestones (notes 26–28).
- **No `ThemeData`, no new dependencies, no token/theme system** (spec Guards). Stay on Material 3 defaults; consistency comes from shared *patterns*, not a theme. Only `package:flutter/material.dart` and (where a widget maps a kit enum to a color) `package:camera_ppg_kit/camera_ppg_kit.dart` may be imported.
- **These are kit-style presentation widgets, not example instrumentation** — keep them log-free. The `ppgTap`/`ppgLog` interaction logging (`auto_detect/log.dart`) stays in the screen handlers, added when the screens are rebuilt, not inside these leaf widgets.
- **Match the exact spacing rhythm and color semantics already inlined** in the current screens so the rebuilds are a faithful recompose:
  - Card rhythm: `Card` → `Padding(EdgeInsets.all(16))` → `Column(crossAxisStart)`, `SizedBox(8)` under the header, `SizedBox(12)` between cards on a screen.
  - Banner style (from `source_screen.dart:_stateBanner` / `streams_screen.dart:_stateBanner`): full-width `Container`, `padding: EdgeInsets.all(12)`, `color.withValues(alpha: 0.1)` fill, `BorderRadius.circular(8)`, `Border.all(color: color)`, centered bold `fontSize: 16` label in `color`.
  - Chip style (from `_qualityAndPresenceRow`): `Chip` with `backgroundColor: color.withValues(alpha: 0.15)` and bold `labelStyle` in `color`.
  - Grey helper/timestamp text is `fontSize: 12, color: Colors.grey`.

## Tasks

### Phase 1: Color foundation + primitives

- [x] **Task 1: Local status-color map**
  Files: `example/lib/widgets/status_color.dart`
  Add the local semantic palette kept inside `widgets/` (explicitly **not** a global token file, per spec). Expose the five named colors from the spec — good→`Colors.green`, fair→`Colors.orange`, poor→`Colors.red`, idle→`Colors.grey`, pending→`Colors.blue` — as `const` values, plus a convenience `Color qualityColor(SignalQuality? q)` that folds `good/fair/poor` and `null`→idle-grey (the exact switch currently inlined in every screen's `_qualityAndPresenceRow`). Import the kit barrel `package:camera_ppg_kit/camera_ppg_kit.dart` for `SignalQuality`. This is the color source consumed by Tasks 4; keep it a plain library, no widgets.

- [x] **Task 2: SectionCard**
  Files: `example/lib/widgets/section_card.dart`
  `SectionCard({required String title, String? subtitle, required Widget child})` — a `Card` → `Padding(EdgeInsets.all(16))` → `Column(crossAxisAlignment: start)` with a bold header `Text(title)`, an optional grey hint `subtitle` (`fontSize: 12, color: Colors.grey`) when non-null, `SizedBox(height: 8)`, then `child`. This is the 16/12/8 rhythm carrier for the rebuilds. Pure stateless widget, `const` constructor.

- [x] **Task 3: MetricRow + LabelRow**
  Files: `example/lib/widgets/metric_row.dart`
  Two aligned label→value rows, each `Padding(EdgeInsets.symmetric(vertical: 4))` → `Row`.
  - `MetricRow(String label, num? value, {String unit = '', int decimals = 3, double labelWidth = 140, Color? valueColor, bool mono = false})` — fixed-width label (`SizedBox(width: labelWidth)`) then the value: render `'—'` when `value == null`, else `value.toStringAsFixed(decimals)` with `unit` appended (space only when unit is non-empty); apply `fontFamily: 'monospace'` when `mono` (for live numbers) and `color: valueColor` when set.
  - `LabelRow(String label, String value)` — label→string value for enum display (finger-presence, camera lens, etc.), same row rhythm, no numeric formatting.
  Both stateless, `const` constructors.

- [x] **Task 4: StatusChip + StateBanner** (depends on Task 1)
  Files: `example/lib/widgets/status_chip.dart`, `example/lib/widgets/state_banner.dart`
  - `StatusChip(String label, Color color)` — a `Chip` with `backgroundColor: color.withValues(alpha: 0.15)` and a bold `labelStyle` in `color` — the extraction of the inline SQI chip in `source_screen`/`streams_screen`. Optionally `visualDensity: VisualDensity.compact`.
  - `StateBanner(String label, Color color)` — the bordered tinted full-width container extracted verbatim from `source_screen.dart:_stateBanner` (`padding: EdgeInsets.all(12)`, `color.withValues(alpha: 0.1)` fill, `BorderRadius.circular(8)`, `Border.all(color: color)`, centered bold `fontSize: 16` label in `color`).
  Callers pass the color (from Task 1's map); the widgets themselves stay enum-agnostic. Both stateless, `const` constructors.

- [x] **Task 5: Async-state helpers**
  Files: `example/lib/widgets/async_states.dart`
  Three small centered presentation widgets so the rebuilt screens can render real `AsyncValue.when(loading/error/data)` and empty states instead of today's `.value ?? default`:
  - `AsyncLoader` — centered `CircularProgressIndicator` (optionally with a caption).
  - `AsyncEmpty(String message)` — centered icon + grey message (the "waiting for signal…" state).
  - `AsyncError(Object error)` — centered error icon + `error.toString()` text in the poor/red color.
  Keep them layout-only (`Center` + `Column`), no Riverpod imports — the screens own the `.when(...)` wiring in notes 26–28. Stateless, `const` where possible.

### Phase 2: Barrel + verify

- [x] **Task 6: Widgets barrel** (depends on Tasks 1–5)
  Files: `example/lib/widgets/widgets.dart`
  A single re-export barrel (`export 'section_card.dart';` … one line per file above) so the screen rebuilds import `../widgets/widgets.dart` once. Mirrors the kit's own barrel convention (base rules) for the example's local widget set.

- [x] **Task 7: Verify the widgets compile clean** (depends on Task 6)
  Files: (no source change)
  Run `/usr/local/bin/flutter analyze` from the `camera_ppg_kit` root and confirm the new `example/lib/widgets/` files produce no analyzer errors/warnings (spec Verify: "the widgets compile"). No test file and no throwaway smoke screen is committed — the spec's smoke screen is a manual sanity check, and adding a demo screen would violate the "foundation only, screens untouched" guard. Fix any analyzer findings in the widget files before finishing.

## Commit Plan
- **Commit 1** (after tasks 1–3): "Add example widget-kit color map, SectionCard, and metric rows"
- **Commit 2** (after tasks 4–5): "Add StatusChip, StateBanner, and async-state helpers to example widget kit"
- **Commit 3** (after tasks 6–7): "Add example widgets barrel and verify analyzer clean"
