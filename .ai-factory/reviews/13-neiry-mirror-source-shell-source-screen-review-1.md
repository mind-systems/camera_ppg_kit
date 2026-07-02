# Code Review: Neiry-mirror source shell + Source screen

**Plan:** `.ai-factory/plans/13-neiry-mirror-source-shell-source-screen.md`
**Spec:** `.ai-factory/notes/22-neiry-mirror-source-shell.md`
**Diff reviewed:** `main.dart`, `providers/session_config_provider.dart` (new), `screens/source_screen.dart` (new), `screens/kit_api_tab.dart`; cross-checked against untouched guards (`services/camera_ppg_service.dart`, `providers/camera_ppg_service_provider.dart`, `providers/stream_providers.dart`, `auto_detect/auto_detect_screen.dart`) and the kit `lib/src/processing/{session_policy,rr_acceptance}.dart`.
**Risk:** 🟢 Low — no runtime/correctness/security bugs. One low-severity maintainability finding (non-blocking).

## What was verified

- **All-mounted shell + sole ownership (load-bearing property).** `main.dart` replaces `_TabShell`'s `TabController`/`TabBarView` with a `Scaffold` + `NavigationBar` + `IndexedStack`. All three branches are children of one `IndexedStack`, so switching never disposes a screen or drops provider subscriptions; the `CameraPpgService` singleton remains the sole lifecycle owner (the shell only *commands* it). Matches spec note 22.
- **Raw exclusivity hook is correctly enum-gated.** The one navigation hook fires on `branch == _Branch.raw` (not a literal `if (index == 2)`), satisfying plan-review #1 — a future Calibration branch inserted before Raw will not mis-fire the hook. `stopMeasurement()` is fire-and-forget with the documented, accepted residual race (same as the prior shell, direction inverted). Verified `AutoDetectScreen` opens the camera only inside its awaited `detectCoveredCamera` round-trip on explicit Start and holds no long-lived `CameraController`, so keeping Raw mounted never contends for the camera while a kit screen is active.
- **`sessionConfigProvider` is a faithful single source of truth.** `SessionConfig.defaults()` seeds from `RrAcceptance()`/`SessionPolicy()` (no invented numbers). Each mutator reconstructs the nested policy/acceptance preserving all other fields. **Checked the kit classes directly:** `SessionPolicy` has exactly the 4 reconstructed fields (`warmupDuration`, `targetDuration`, `silenceWindow`, `sqiFloor`) and `RrAcceptance` exactly the 4 (`minRrMs`, `consistencyThreshold`, `coldStartBeats`, `medianWindow`) — no hidden 5th field is silently reset on a knob edit. `copyWith` always returns a fresh instance, so Riverpod (no `==` override → reference inequality) always notifies; edits never get swallowed.
- **`[debug]` panel re-seed pattern preserved.** `_debugPanel` reads `ref.watch(sessionConfigProvider)`, so a notifier write rebuilds the panel; `_intField`/`_doubleField` keep `key: ValueKey('$label-$value')` bound to the provider-derived value + `initialValue`, so a submitted edit round-trips and re-seeds the field correctly (plan-review #3).
- **`_start` reads the in-force config at start time** (`ref.read(sessionConfigProvider)`) and forwards `policy`/`acceptance` — knob changes apply on the next (re)start, as specified. The `done`-recovery path (`stopMeasurement()` before restart from terminal `done`) and the `isRunning`/`canStop` derivation are carried over intact.
- **Kit-API stripped to a pure consumer.** No lifecycle, camera, permission, or config code remains; imports reduced to the barrel + `stream_providers.dart` (no dangling references to removed `_start`/`_stop`/`permission_handler`/`session_config_provider`). Still a `ConsumerStatefulWidget` only for the `_rrHistory` UI list, using the existing provider `ref.listen`s — no new subscription.
- **Guards respected.** `git status` shows only `main.dart` + `kit_api_tab.dart` modified and the two new files; the service, service-provider, stream-providers, recorder, and `auto_detect_screen.dart` are untouched. Riverpod v3 `Notifier`/`NotifierProvider` usage matches the existing `BpmNotifier`.

## Findings

### [Low, non-blocking] `main.dart` — `IndexedStack` children are a hardcoded list, not enum-derived; doc comment overstates the safety

`main.dart:32-37` documents the `_Branch` enum as the thing `_ShellState` "builds both the `IndexedStack` children and the `NavigationBar` destinations from." In fact only the **destinations** are enum-derived (`for (final branch in _Branch.values)`, lines 107-114). The **children** are a separate hardcoded `const [SourceScreen(), KitApiTab(), AutoDetectScreen()]` (lines 98-102), positionally coupled to the enum by convention only.

Impact today: none — order matches (`source=0`, `kitApi=1`, `raw=2`), so `_selected.index`, `selectedIndex`, and `_Branch.values[index]` all line up. The critical plan-review #1 concern (hook firing on the wrong branch) is fully resolved because the hook is enum-gated, not index-gated.

Forward-compat: the next milestone (note 21) inserts a Calibration branch *before* Raw. Adding `calibration` to the enum shifts `_Branch.raw.index` to 3, but the hardcoded children list would still have `AutoDetectScreen` at index 2 unless the implementer *also* inserts the Calibration screen into the children list at the matching position. So the children list is not "index-shift-safe" on its own, and the doc comment claiming the children are built from the enum is inaccurate. Suggest either building the children from the enum (a `switch (branch)` mapping inside the same loop that builds destinations) or tightening the comment to say the children list must be kept positionally in sync with `_Branch`. Cosmetic/maintainability only — no runtime effect in this milestone.

## Notes (no action)

- **Behavior change (benign):** because `IndexedStack` builds all children eagerly, `AutoDetectScreen.initState`'s `_enumerate()` and `SourceScreen`'s post-frame `_loadCameras()` now run at app launch rather than on first branch visit. Both are enumeration-only (no camera open, no torch), so this is harmless — worth awareness, not a fix.
- **AppBar/SafeArea (plan-review #4) handled:** the shell provides a shared per-branch `AppBar` and Source/Kit-API wrap their bodies in `SafeArea`; Raw remains a nested `Scaffold` with its own `AppBar` as accepted.
- **Untouched-provider doc drift (plan-review #5)** remains (comments still say "Kit-API tab") — correctly deferred to a future doc pass; these are guard files.

Overall: implementable and correct as written. The single finding is a low-severity maintainability/documentation nit that does not affect this milestone's runtime behavior.
