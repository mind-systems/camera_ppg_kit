# Preview square in the Signal card + reset on Stop

**Date:** 2026-07-03
**Source:** conversation context (Source-screen layout + stale-card bug)

## Precondition

Note 35 has shipped the kit's `CameraPpgSession.buildPreview() → Widget?` surface. This
task is the **example-side placement/layout** of that preview and a card-reset bug fix —
it adds no kit surface. Note 35's own placement (a standalone preview `SectionCard`) is
superseded by this layout; do not build both.

## Current state

`source_screen.dart` `_signalCard()` is a `SectionCard` titled "Signal" holding a
`Column` of:
1. the SQI chip — `qualityAsync.when(data: StatusChip('SQI: <name>', …), loading:
   AsyncEmpty('waiting for signal…'), error: AsyncError(...))`,
2. a spacer,
3. `LabelRow('Finger', presenceLabel)`.

Two problems: there is no camera preview here, and this card **does not reset when Stop
is pressed** — the SQI chip keeps showing its last value (e.g. "SQI: good") after the
measurement is stopped, because `qualityProvider` (a `StreamProvider` over the
long-lived `qualityStream`) retains its last emitted value and nothing repaints it to
the waiting state.

## The change (example only)

Recompose `_signalCard()`:

- **Top row** — a `Row` with the SQI chip on the left and, **to its right, a small
  square camera preview**: roughly the same width as the SQI chip (two ~equal-width
  children), a square `AspectRatio(1)` with rounded-corner clip, fed by
  `service.buildPreview()` (note 35). Not a full-width video panel — a small square.
- **Finger row** — the `LabelRow('Finger', presenceLabel)` stays **exactly as it is
  today**, its own row below the SQI+preview row. No change.
- **Reset on Stop** — the whole card returns to its initial state when the source is not
  measuring: the SQI area shows `AsyncEmpty('waiting for signal…')` and the preview
  square shows its placeholder, gated on the lifecycle state (note 33's `lifecycleProvider` /
  `service.isMeasuring`) rather than the last stream value — so pressing Stop clears
  "SQI: good" back to waiting and blanks the preview, instead of freezing the last frame
  state.

## Verify

- On device: while measuring, the Signal card shows the SQI chip and, to its right, a
  small live square of the covered lens; the Finger row is unchanged below.
- Press Stop → the SQI chip returns to "waiting for signal…" and the preview square
  blanks to its placeholder (no stale "SQI: good", no frozen frame).
- Start again → both repopulate.

## Guards

- Example only — no kit `lib/` change (that was note 35). No `done` state (note 23).
- Do not cache a stale preview widget across Stop — re-query `buildPreview()` each build,
  and gate on lifecycle, not on the last quality emit.
- Keep the Finger row identical to today; only the SQI+preview row and the reset
  behavior change.
