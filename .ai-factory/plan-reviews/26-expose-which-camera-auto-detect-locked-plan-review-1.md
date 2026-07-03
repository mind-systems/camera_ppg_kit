## Code Review Summary

**Files Reviewed:** 1 plan (`26-expose-which-camera-auto-detect-locked.md`), cross-checked against `lib/src/api/camera_ppg_session.dart`, `lib/src/models/camera_ppg_camera_info.dart`, `lib/camera_ppg_kit.dart`, `example/lib/screens/source_screen.dart`, `example/lib/widgets/metric_row.dart` + barrel, `example/lib/services/camera_ppg_service.dart`
**Risk Level:** 🟢 Low

### Context Gates
- **Roadmap alignment (WARN → OK):** The milestone `Expose which camera auto-detect locked` is the open task at `ROADMAP.md:71`, phase *7.6 — Camera-selection verification*, complement to note 35's live preview (`ROADMAP.md:70`). The plan matches the contract line precisely: `resolvedCamera` accessor + lock/clear stream, returns the existing `CameraPpgCameraInfo` (never `CameraDescription`), clears to null on `_release()`, shows "Locked lens: id (type)" in the Source screen. Linkage present.
- **Governing spec (`notes/36-resolved-camera-accessor.md`):** All four spec guards are honored by the plan — (1) map to `CameraPpgCameraInfo` at the edge, never leak `camera` types; (2) accessor **and** watchable stream since lock is async inside `start()`; (3) clears to null on `_release()`; (4) independent of note 35. The three display states (`—` / `id (type)` / `auto-detecting…`) and the pinned-`useCamera` case are all covered. Plan is a faithful decomposition of the spec.
- **Architecture / Rules:** No `.ai-factory/skill-context/aif-review/SKILL.md` present. No `RULES.md` convention conflicts. The kit's "no `package:camera` type across a public signature" invariant and the example's "`camera_ppg_service.dart` stays `flutter`-free" invariant are both explicitly preserved by the plan.

### Correctness Verification (plan vs. actual code)
Every anchor the plan cites was checked against the source and is accurate:

- **Constructor / dispose symmetry** — broadcast controllers are built in the initializer list (`camera_ppg_session.dart:56-64`) and closed in `dispose()` (`424-428`). Adding `_resolvedCameraController` alongside both is correct and consistent.
- **`_setResolvedCamera` shape** — mirrors `_setState` (`642-648`): dedupe → store → emit guarded by `!isClosed`. Sound.
- **Edge-mapping extraction** — the inline `CameraDescription → CameraPpgCameraInfo` map (`id: d.name`, `lensType: d.lensType.name`, `flashAvailable: true`) lives at `availableCameras()` (`684-690`); extracting it to `_toCameraInfo` and reusing it on the lock path centralizes the edge mapping correctly and matches the model's field contract (`camera_ppg_camera_info.dart:16-42`).
- **Lock-path call site** — the promotion block assigning `_controller`/`_frameIsolate`/`_sub` just before `_setState(MeasurementState.warmup)` is at `366-374`; it is past every `stale()` check (no staleness race), and `description` there holds the resolved lens for **both** the auto-detect (`273`) and pinned-`useCamera` (`261`) paths, so a single `_setResolvedCamera(_toCameraInfo(description))` covers both — exactly as the plan claims.
- **`_release()` clear** — `_acceptance.reset()` / `_dehalving.reset()` cleanup is at `460-461`; placing `_setResolvedCamera(null)` there guarantees the lens clears on stop, dispose, and every failed-`start()` path (all route through `_release()`).
- **Barrel** — `camera_ppg_kit.dart:4-5` already exports the whole session file and `camera_ppg_camera_info.dart`, so no barrel edit is needed; the plan correctly says so and correctly defers note 19's Phase-10 freeze enumeration.
- **Example side** — `LabelRow(label, value)` exists (`metric_row.dart:52-58`) and is exported via `widgets/widgets.dart`; `_cameraOverrideCard` receives `locked = lifecycle != SourceLifecycle.idle` (`source_screen.dart:144`); the stale dartdoc the plan rewrites is exactly at `306-310`; reading `ref.read(cameraPpgServiceProvider).session?.resolvedCamera` fresh each build mirrors `_previewCard()`'s `session?.buildPreview()` (`244`) and rides the same `ref.watch(lifecycleProvider)` rebuild. All accurate.

No missing steps, no wrong file paths, no incorrect API usage, no migrations required (Flutter plugin), no security surface touched.

### Minor Issues (non-blocking)

1. **`source_screen.dart` — "auto-detecting…" also renders during teardown.**
   The service nulls `_session` *before* awaiting `session.dispose()` (`camera_ppg_service.dart:231-233`), so during the `stopping` lifecycle `session?.resolvedCamera` is already `null` while `locked` (`lifecycle != idle`) is still `true`. With the plan's three-state logic (idle→`—`; resolved!=null→id; else→`auto-detecting…`), the row will read **"Locked lens: auto-detecting…"** during `stopping`, which is misleading (nothing is auto-detecting; it's tearing down). Cosmetic only — the preview card degrades to its placeholder in the same window without a wrong label. Consider gating the `auto-detecting…` branch on `lifecycle == starting` specifically (falling back to `—` for `stopping`), or accept the minor inaccuracy. Worth one line in the implementation to decide deliberately rather than by accident.

### Positive Notes
- The plan reasons from the real code, not an imagined shape — every line/anchor it cites was verifiable and correct, including the subtle "one `description` covers both auto-detect and pinned paths" observation and the placement past the staleness checks.
- Boundary discipline is explicit and preserved on both sides: no `CameraDescription` crosses the barrel (mapped via the shared `_toCameraInfo` helper), and the example reads the getter directly so no `flutter`-importing service getter is added.
- Lifecycle correctness (clear-on-`_release()`) is baked in at the single teardown chokepoint, so no stale lens can survive any stop/dispose/failed-start path.
- Adding the watchable `resolvedCameraStream` even though the example consumes only the synchronous getter satisfies the spec's "small stream/notifier the host can watch" and future-proofs a real host consumer — not over-engineering given the spec asks for it.

The plan is solid and implementation-ready. The single item above is a cosmetic refinement, not a correctness blocker.

PLAN_REVIEW_PASS
