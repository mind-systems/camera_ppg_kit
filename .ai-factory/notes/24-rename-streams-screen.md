# Example — Rename the Kit-API Consumer Screen to "Streams"

**Date:** 2026-07-03
**Source:** user observation ("the Kit-API screen shows the data stream but is named Kit API"); note 22 (which stripped it to a pure consumer); neiry example (`streams_screen.dart` — the consumer-display screen is named for what it shows)

## Key Findings

- After note 22 the "Kit API" tab is a **pure consumer** — it only `ref.watch`es and displays the live data stream (RR + `isArtifact`, derived BPM, SQI, finger-presence, `MeasurementState`). It no longer starts/stops anything. Naming it "Kit API" is misleading; it should be named for what it shows.
- Neiry's example names its equivalent screen **Streams** (`streams_screen.dart`) — the consumer-display screen. Mirror that.

## Details

- **Tab label:** "Kit API" → **"Streams"** (in `example/lib/main.dart`'s shell). ("Data"/"Live" are acceptable alternatives — the label is the user's call; this note assumes "Streams" for neiry parity.)
- **File/class (consistency):** `example/lib/screens/kit_api_tab.dart` → `streams_screen.dart`; class `KitApiTab` → `StreamsScreen`. Update the import + branch reference in `main.dart`.
- **No behavior change** — the screen's consumer logic (providers it watches, the display) is untouched; this is a pure rename.

## Guards

- Pure rename: do not alter what the screen watches or displays. No lifecycle/camera logic here (note 22 owns the source).
- Independent of the open-ended-session fix (note 23) — either can land first.

## Verify

- The data-display tab reads **"Streams"** and still shows the live streams; the app builds and runs.
- `grep -rn 'KitApiTab\|kit_api_tab' example/lib` → no stale references.
