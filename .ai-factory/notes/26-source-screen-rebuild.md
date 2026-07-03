# Example — Rebuild the Source Screen on the Widget Kit

**Date:** 2026-07-03
**Source:** example UX quality pass (note 25 kit); note 22 (Source screen behavior — unchanged); note 23 (open-ended — removes the dead `done` arm)

## Key Findings

- `source_screen.dart` is the crudest surface: raw `Container` + `BoxDecoration` state banner, inline `Chip`s, `ExpansionTile` for `[debug]`, inline color logic, plain buttons. Recompose it on note 25's widget kit to neiry's card-section bar.
- **Presentation only** — the sole Start/Stop control, camera override, permission flow, and the `[debug]` tuning bound to `sessionConfigProvider` all keep their behavior (note 22).

## Details

Recompose `build` as a `ListView` of `SectionCard`s (note 25):

- **`StateBanner`** for `MeasurementState` (drop the inline `Container`). No `done`/"Complete" arm — note 23 removes that state.
- **Control card** — Start/Stop as full-width semantic buttons (`ElevatedButton` / `OutlinedButton`), `Start` disabled while running, `Stop` while `!idle`.
- **Signal card** — SQI as a `StatusChip` (good/fair/poor), finger-presence as a `LabelRow`; wrap the reads in async states (`AsyncEmpty`/`AsyncLoader`) so pre-signal reads show "waiting…" not a blank chip.
- **Camera-override card** — the dropdown + Refresh, unchanged logic.
- **`[debug]` tuning card** — keep the `sessionConfigProvider` knobs (note 22); render the fields inside a `SectionCard` (an `ExpansionTile` inside is fine) using the shared field widgets.
- **Error banner** — via a shared component (reuse the `StateBanner`/error style).

## Guards

- No lifecycle/camera/config-provider logic change — note 22 stands; this is a visual recomposition.
- Assumes note 23 landed (no `MeasurementState.done`); if not, do not re-introduce a "Complete" arm.
- Kit `lib/` untouched.

## Verify

- Source screen reads as neiry-style cards; Start/Stop, camera override, and `[debug]` tuning still work; SQI/finger show waiting states before signal.
