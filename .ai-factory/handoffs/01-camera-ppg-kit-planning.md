# Handoff — camera_ppg_kit planning complete, implementation not started

## 1. Frame
`camera_ppg_kit` is a brand-new Flutter plugin (camera + flash → contact-PPG → RR intervals) for the `mind` monorepo; this session scaffolded it and fully planned it (12 phases, 19 spec notes) but wrote **zero implementation code** — the chat is compacted, but all knowledge is durable in `.ai-factory/`; rehydrate from those files, don't trust memory.

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `.ai-factory/ROADMAP.md` — the index: 12 phases, every task carries a `Spec:` pointer to its note. Lead here.
- `.ai-factory/ARCHITECTURE.md` — Structured Modules; the barrel is the contract; the dependency/anti-pattern rules every note assumes.
- `.ai-factory/DESCRIPTION.md` — what the kit is + the three hard constraints (signal-based camera auto-detect, FPS sensitivity, still-finger 30–60 s).
- `CLAUDE.md` — single source of truth for working in this repo (AGENTS.md just points here).

### Read on demand
- `.ai-factory/notes/01..09-*.md` — foundational phase specs (spike → channel → models → API → session policy), hand-written this session.
- `.ai-factory/notes/10..19-*.md` — later phase specs (native bridges, signal processing, example, service, hardening, integration), written by a multi-agent workflow this session.
- `/Users/max/projects/mind/neiry_kit/` — the sibling kit this one mirrors; prior art referenced throughout (esp. `lib/src/processing/ppg_peak_detector.dart`, `lib/src/models/rr_interval.dart`, `example/lib/services/neiry_service.dart`, `docs/guides/teardown.md`).
- `/Users/max/projects/mind/mind_mobile/docs/biometrics/active-rr-source.md` — the RR-source contract this kit must satisfy for drop-in (Phase 12).

## 3. Current state

**Done:**
- Feasibility settled: camera contact-PPG via `flutter_ppg` 0.2.4 + `camera` is viable; RR intervals + SQI come from `flutter_ppg`.
- Plugin scaffolded (`flutter create --template=plugin`, org `com.mind`, android+ios), deps `flutter_ppg` + `camera` added.
- AI Factory context: config.yaml (ui=ru, artifacts=en), DESCRIPTION, ARCHITECTURE (Structured Modules / Technical Layers), rules/base, slim AGENTS.md, README rewritten, `.mcp.json` + `.ai-factory.json` (filesystem MCP only), `.claude/settings.local.json`.
- ROADMAP decomposed: 12 phases → 20 atomic tasks (1 done), all 19 pending tasks have real two-tier spec notes; 0 `<note pending>` left; every `Spec:` path verified to resolve.
- Standalone git repo with correct remote `mind-systems/camera_ppg_kit.git`; scaffold committed as `7d3f86c`.

**In-flight:**
- Nothing actively mid-edit. Planning phase is closed; implementation has not begun.

**Uncommitted working-tree state:**
- `.ai-factory/ROADMAP.md` (untracked) and `.ai-factory/notes/` (all 19 notes, untracked) — created after commit `7d3f86c`. Everything else is committed.

## 4. Next step
Commit the planning artifacts (`.ai-factory/ROADMAP.md` + `.ai-factory/notes/`) — **ask the user before committing** — then start **Phase 2 — Hardware feasibility spike** (it gates the whole roadmap). Begin with note `01-camera-enumeration-probe.md`: run `/aif-plan` on that task to turn the spec note into an implementation plan, then `/aif-implement`. Do not build native bridges (Phase 7) or hardening (Phase 11) before the spike's device-support matrix (note 03) produces a go/no-go.

## 5. Working discipline
- User communicates in Russian; all files/artifacts in English.
- Confirm before irreversible/outward actions. **Never commit or push without explicit permission** — this session committed only when the user said so, and restored a remote after a mistake.
- Mirror `neiry_kit` structure deliberately (the user values cross-kit consistency) — when unsure how to shape something, look at how neiry did it first.
- Prefer dedicated tools; use `flutter pub add` (never hand-edit `pubspec.yaml`); invoke Flutter as `/usr/local/bin/flutter`.

## 6. Error log
- **Remote clobber.** `camera_ppg_kit` had no own `.git` at first — it sat inside the root monorepo repo (`/Users/max/projects/mind/.git`, remote `mind-systems/mind_context.git`). Running `git remote set-url origin …camera_ppg_kit.git` "inside" the kit actually rewrote the **monorepo's** origin. Fix applied: (1) restored root origin → `https://github.com/mind-systems/mind_context.git`; (2) `git init` in the kit; (3) set the kit's own origin → `https://github.com/mind-systems/camera_ppg_kit.git`. Lesson: this kit is now its own repo — always run git **inside** `camera_ppg_kit/`, and the monorepo ignores the folder via root `.gitignore`.

## 7. Orientation
- **"RR" = R-R inter-beat intervals (cardiac), NOT respiratory rate.** It is the same data type neiry's `RRInterval` carries.
- **`flutter_ppg` already does peak detection** and emits RR + SQI. The kit ports **only** neiry's `_gate()` acceptance logic (note 12) — never `_findPeaks`/refractory/buffer. Duplicating the DSP is the trap.
- **One example app, two maturity stages (reconceived 2026-06-21):** there is a *single* `example/` developer playground. Phase 2 (notes 01/02) is its raw first panels — signal-based camera auto-detect + raw stream inspector, used as the feasibility gate. Phase 9 (note 14) grows the *same* app into the full kitchen-sink: stream inspector + settings playground for the kit-integrating developer. Not an end-user measurement UX — no session storyline, no end-of-session summary. (Supersedes the earlier "two separate screens, don't merge" framing.)
- **`neiry_kit` (sibling/template) vs `camera_ppg_kit` (this repo).** Notes reference neiry files by absolute path; do not edit neiry when implementing here.
- **Per-beat vs session-state:** the acceptance gate (note 12) flags `isArtifact` per beat; session policy (note 09) decides warm-up/poorSignal/done. Separate concerns, separate files.

## 8. Domain model spine
- `RrInterval` is **shape-identical to neiry's `RRInterval`**: `{ int intervalMs; DateTime timestamp; bool isArtifact }`. Don't re-litigate field names — identity is what lets `mind_mobile` consume camera and worn sources through one contract. (note 05)
- The kit emits **RR intervals + signal quality only**; BPM/HRV are the consumer's to derive. Don't add them. (DESCRIPTION, note 05)
- Expected conditions (permission denied, no finger, poor signal, unsupported device) cross the boundary as **typed values, never thrown** across the channel. (ARCHITECTURE, note 06)
- Architecture is **Structured Modules (Technical Layers)**: `lib/camera_ppg_kit.dart` barrel is the public contract; `lib/src/{api,models,channel,processing,util}` is private. (ARCHITECTURE)

## 9. Hard rules
- All files English (monorepo `CLAUDE.md`); communication Russian.
- Never commit/push without explicit user permission. Commit messages: sentence case, no `feat:`/`fix:` prefix, no body for single-concern; end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- This kit owns **no** `.proto`/wire contract — do not add gRPC here.
- `flutter pub add` only; `/usr/local/bin/flutter`.
- Git operations run **inside `camera_ppg_kit/`** (separate repo).

## 10. Cross-cutting contracts / invariants checklist
These names/shapes recur across the 19 notes and must stay identical everywhere:
- `RrInterval { int intervalMs; DateTime timestamp; bool isArtifact }` — never `rrMs`/`durationMs`; never add an upper RR bound.
- `SignalQuality { good, fair, poor }` + `SignalQuality.fromSnr(double)` — thresholds are spike-tunable constants.
- `MeasurementState { idle, warmup, measuring, done, poorSignal }` — used by both the channel enum and `stateStream`.
- `CameraPpgError` — typed states: permissionDenied, cameraUnavailable/torchUnavailable, unsupportedDevice (deny-list driven), noFinger, poorSignal.
- Channel holders: `CameraPpgChannels` / `CameraPpgMethods` / `CameraPpgEvents` — the enums are the durable deliverable. Enumeration + selection are Dart-side (note 03: `availableCameras()` lists every rear lens on iOS, one logical back on Android), so the only possible channel method is a `setTorch` fallback (notes 10/11 are deletion candidates); the holder may stay unused.
- Barrel rule: nothing from `flutter_ppg` / `camera` / `MethodChannel` may appear in any public signature — convert at the api/processing edge.
- `lib/src/processing/` is pure Dart (no Flutter/camera/channel imports) → isolate-safe + unit-testable. The RR gate (`rr_acceptance.dart`) and any reduction live here.

## 11. Per-unit map with watch-points
- **Phase 1 — Scaffold** `[x]` (`7d3f86c`). Done; nothing to verify.
- **Phase 2 — Hardware spike** (notes 01/02/03). Watch: this is the gate — its device-support matrix + go/no-go decides whether bridges/hardening even ship. Harness must run on a quiet screen or the FPS number it measures is invalid.
- **Phase 3 — Channel contract** (note 04). Watch: keep the native surface tiny — do NOT add channels for data `flutter_ppg` already provides in Dart.
- **Phase 4 — Dart models** (notes 05 data, 06 state/error). Watch: `RrInterval` field-name identity with neiry; reuse neiry's `orNull` sentinel; no `throw` across the channel.
- **Phase 5 — Dart API** (notes 07 session, 08 selection). Watch: `flutter_ppg`/`camera` types must not leak through the barrel; streams stay open across stop/start (neiry's "fed-on-connect" pattern).
- **Phase 6 — Session policy** (note 09). Watch: keep it a pure function of (signal events, elapsed time) so it's testable without hardware; it sets session *state*, not per-beat `isArtifact`.
- **Phase 7 — Native bridges** (notes 10 iOS, 11 Android). Watch: torch ownership pitfall — the `camera` plugin holds the capture device during measurement, so torch likely must be driven via the capture session's `FLASH_MODE_TORCH`, not `CameraManager.setTorchMode`/standalone — confirm during impl. Errors are returned values, not crashes.
- **Phase 8 — Signal processing** (notes 12 gate, 13 isolate). Watch: port ONLY `_gate()` (no peak detection); whether `FlutterPPGService.processImageStream` is isolate-safe must be empirically confirmed before choosing the isolate variant.
- **Phase 9 — Example app** (notes 14 screen, 15 permissions). Watch: subscriptions live in Riverpod providers, NOT `StreamBuilder` (neiry lesson); iOS needs `NSCameraUsageDescription` or the camera plugin crashes on first use.
- **Phase 10 — CameraPpgService singleton** (note 16). Watch: plain Dart, no Flutter/Riverpod imports; broadcast controllers stay open across stop/start (mirror neiry's `NeiryService`).
- **Phase 11 — Hardening** (notes 17 lifecycle, 18 gating). Watch: the camera is an exclusive OS resource — ordered release (isolate+subs → stopImageStream → torch off → controller.dispose) and release/re-init on app background via `WidgetsBindingObserver`; double-dispose guard.
- **Phase 12 — Integration readiness** (note 19). Watch: the `lib/Biometrics/` adapter + `camera_ppg` source tag live in **`mind_mobile`, not this kit**; this note only freezes the barrel surface the adapter will consume.
