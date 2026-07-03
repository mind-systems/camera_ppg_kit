# Code Review: Rename the Kit-API consumer screen → "Streams"

**Scope:** `git diff HEAD` — pure rename of the example-app consumer screen.
**Files changed (code):** `example/lib/screens/kit_api_tab.dart` → `streams_screen.dart` (renamed), `example/lib/main.dart`, `example/lib/screens/source_screen.dart`.

## Verification performed

- **Full read of the renamed file** (`streams_screen.dart`): class `StreamsScreen` + state `_StreamsScreenState` renamed consistently, including the `createState()` return type. The widget body (providers watched, `ref.listen` subscriptions, rolling list, display) is byte-for-byte unchanged from the pre-rename version — confirmed by the diff's `similarity index 95%` (the 5% delta is exactly the class/doc-comment lines). No behavior change, matching the plan's guard.
- **`main.dart`:** import, `_Branch.streams('Streams')` enum case, `_screenFor` switch arm (`_Branch.streams => const StreamsScreen()`), and the present-tense `_Shell` doc comment all updated. Enum ordering (source, streams, calibration, raw) and the Raw-exclusivity hook keyed on `_Branch.raw` are untouched — no positional/index breakage. The switch remains exhaustive over `_Branch`, so it compiles.
- **`source_screen.dart`:** three comment-only references to `kit_api_tab.dart`/`kit_api_tab` retargeted to `streams_screen.dart`. No code touched.
- **Stale-identifier sweep:** `grep -rn 'KitApiTab\|kit_api_tab\|kitApi' example/lib` → **no matches**. Every live identifier and file reference is updated, so the app will compile and the only importer (`main.dart`) resolves correctly.
- **Test surface:** `example/test/` does not reference the old class/file (no matches), so nothing in tests breaks.

## Findings

No correctness, security, or runtime bugs. The rename is complete and internally consistent.

### Non-blocking observations

- **Residual conceptual "Kit-API" comments remain** in six files (`main.dart:72`, `stream_providers.dart:7`, `camera_ppg_service_provider.dart:5`, `camera_ppg_service.dart:15`, `calibration_screen.dart:213`, `source_screen.dart:13,230`). These are prose/branch-name references, not identifiers, and are out of scope per spec note 24 (which mandates only the label, file, class, and `kit_api_tab` filename references). `main.dart:72` specifically describes the historical `_TabShell` "leaving Kit-API → stop" rule, so leaving it is arguably more accurate than renaming it. This was already flagged in the plan review as intentional/deferred. Not a defect — noted only so the "stale reference sweep" is understood as identifier-scoped, not prose-scoped.

REVIEW_PASS
