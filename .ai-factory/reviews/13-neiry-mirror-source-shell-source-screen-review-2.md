# Code Review (pass 2): Neiry-mirror source shell + Source screen

**Plan:** `.ai-factory/plans/13-neiry-mirror-source-shell-source-screen.md`
**Spec:** `.ai-factory/notes/22-neiry-mirror-source-shell.md`
**Diff reviewed:** `main.dart` (changed since pass 1), plus re-confirmation of `providers/session_config_provider.dart`, `screens/source_screen.dart`, `screens/kit_api_tab.dart` against untouched guards.
**Risk:** 🟢 None — the pass-1 finding is resolved; no new issues.

## Pass-1 finding: resolved

Review-1's single (low, non-blocking) finding was that `main.dart`'s `IndexedStack` children were a hardcoded `const [...]` list while only the `NavigationBar` destinations were enum-derived — making the "index-shift-safe" doc comment inaccurate and requiring manual list/enum sync when the future Calibration branch is inserted.

This is now fixed. `main.dart:54-58` adds `_screenFor(_Branch branch)`, a `switch` mapping each enum case to its screen, and **both** the children (`main.dart:110` — `[for (final branch in _Branch.values) _screenFor(branch)]`) and the destinations (`main.dart:115-122`) are built by iterating `_Branch.values`. The children list and the destinations now share one ordering source (the enum), the exclusivity hook stays enum-gated (`branch == _Branch.raw`, line 88), and `_selected.index` continues to drive both `IndexedStack.index` and `NavigationBar.selectedIndex` consistently. Inserting a Calibration branch before Raw is now genuinely a two-token change (an enum case + a switch arm), and the doc comment (lines 48-53) accurately describes the code. Verified enum order (`source=0`, `kitApi=1`, `raw=2`) matches the iteration order for children, destinations, and `_Branch.values[index]` decode — no off-by-one.

## Re-confirmed (unchanged since pass 1)

- **`sessionConfigProvider`** — mutators reconstruct `SessionPolicy`/`RrAcceptance` preserving all other fields; both kit classes have exactly the 4 reconstructed fields each (checked in pass 1 against `lib/src/processing/`), so no field is silently reset on a knob edit. `copyWith` returns fresh instances → Riverpod always notifies.
- **Source screen** — `[debug]` panel `ValueKey('$label-$value')` re-seed pattern intact; `_start` reads the in-force config via `ref.read(sessionConfigProvider)` (applies on restart); `done`-recovery and `isRunning`/`canStop` derivation carried over correctly; permission flow and camera override relocated intact; body wrapped in `SafeArea`.
- **Kit-API** — stripped to a pure `ref.watch`/`ref.listen` consumer; no lifecycle/camera/config/permission code; imports reduced to the barrel + `stream_providers.dart`; no dangling references.
- **Guards** — `git status` shows only `main.dart` + `kit_api_tab.dart` modified plus the two new files; service, service-provider, stream-providers, recorder, and `auto_detect_screen.dart` untouched.
- **Benign behavior change** (noted, not a fix) — eager `IndexedStack` mounting runs `AutoDetectScreen._enumerate()` and `SourceScreen._loadCameras()` at launch; both enumeration-only, no camera/torch acquisition.

No runtime, correctness, or security problems remain.

REVIEW_PASS
