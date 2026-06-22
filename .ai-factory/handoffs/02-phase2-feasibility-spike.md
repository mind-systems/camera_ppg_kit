# Handoff — Phase 2 Hardware Feasibility Spike (auto-detect + signal panels → go/no-go)

## 1. Frame
`camera_ppg_kit` is a Flutter plugin (rear camera + flash → contact PPG → RR-interval stream) for `mind_mobile`; it is **fully planned in `.ai-factory/` specs but has zero implementation code** (no `lib/src/` yet) — your job is the Phase 2 hardware spike: implement the two raw `example/` panels (notes 01, 02), run them on real devices, and produce the device-support matrix + go/no-go (note 03), which gates whether the rest of the kit ships. The chat that produced these specs is compacted but the knowledge is durable in the files below — rehydrate from them, not from anyone's memory.

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `.ai-factory/ROADMAP.md` — the 12-phase plan and the `---STOP---` gate after Phase 2; read this first to see where your work sits and what it unblocks.
- `.ai-factory/notes/01-camera-enumeration-probe.md` — the **signal-based camera auto-detect** spec (round-trip-on-Start) and the exact spike questions you must answer per device. Title still says "enumeration-probe" (filename kept for stable links) but content is auto-detect.
- `.ai-factory/notes/02-flutter-ppg-harness.md` — the raw `flutter_ppg` signal/FPS panel spec: what to capture (sustained FPS, SQI distribution, RR stability, finger-presence reliability).
- `.ai-factory/notes/03-device-support-matrix.md` — **your deliverable**: matrix columns + go/no-go statement, incl. the ~15-line count-probe snippet and the "does Phase 7 exist" decision.
- `.ai-factory/DESCRIPTION.md` + `camera_ppg_kit/CLAUDE.md` — what the kit is, the three hard constraints, commands, logging policy.

### Read on demand
- `.ai-factory/notes/08-camera-selection-api.md` — how the spike's auto-detect gets productionized later (round-trip in `start()`); useful to keep the panel's logic forward-compatible.
- `.ai-factory/notes/14-example-measurement-screen.md` — the polished Phase-9 playground your raw panels grow into (don't build it now; just don't paint yourself into a corner).
- `.ai-factory/notes/15-camera-runtime-permissions.md` — the permission flow; you need a stripped version (camera permission only) to open the camera in the signal panel.
- `.ai-factory/notes/06-state-error-types.md` — `FingerPresence` (present/absent/over-bright) and `CameraPpgError`, the vocabulary your panel reads.
- `.ai-factory/handoffs/01-camera-ppg-kit-planning.md` — the original planning handoff (broader, pre-pivot context; some framing superseded — trust notes 01/03 over it where they differ).
- `.ai-factory/ARCHITECTURE.md` — module layout + barrel/boundary rules for when implementation starts.

## 3. Current state

**Done:**
- Phase 1 scaffold complete (`7d3f86c`): Flutter-plugin boilerplate, `example/` app, `pubspec` wired to `flutter_ppg` + `camera`, iOS/Android build configs.
- All 12 phases / 19 spec notes written and internally consistent; latest commit `51ed83f` "Roadmap update" holds the full `.ai-factory/` tree.

**In-flight:**
- Nothing in code. Phase 2 is the next executable work and it is **not started**.

**Uncommitted working-tree state:**
- None — everything is committed at `51ed83f`. Working tree clean.

## 4. Next step
Implement and run the Phase 2 spike, in two tiers, **all in `example/` calling `flutter_ppg`/`camera` directly (the kit's `lib/src/` does not exist and must not be built yet — STOP gate)**:
1. **Count-probe first (cheapest, ~15 lines, no permission, no `flutter_ppg`):** drop the `availableCameras()` snippet from note 03 into `example/lib/main.dart`, run on real iOS + Android devices, record rear-`CameraDescription` count per device. Expected: iOS Pro ≈ 2–3 lenses (+`lensType`), Android ≈ 1 logical back. This confirms the source-derived capability and settles "does Phase 7 exist".
2. **Signal/FPS panel (note 02):** add minimal camera permission (iOS `NSCameraUsageDescription` in `example/ios/Runner/Info.plist`, Android runtime request), open the auto-detected camera + torch, stream `CameraImage` → `flutter_ppg`, render raw `PPGSignal` (RR, SQI, SNR, finger-presence, **sustained FPS**). Capture the note-02 metrics on the target device families.
Then write up `note 03`'s matrix + go/no-go and bring it to the user — the decision (ship broadly / allow-list opt-in / shelve) is the user's, you produce the evidence + recommendation.

## 5. Working discipline
- **This repo is plan-first; the user reviews before commits.** Never commit without an explicit instruction (the user says "аммендь"/"закоммить"). Run git **inside `camera_ppg_kit/`** — it is a separate repo from the `mind/` monorepo root.
- The user reasons carefully and **challenges inconsistencies** — expect pushback; verify claims against source (they read `camera_avfoundation`/`camera_android_camerax` sources themselves to settle the iOS/Android question). Don't assert hardware behavior you haven't confirmed.
- Prefer confirm-before-execute on anything outward-facing or hard to reverse. Surface trade-offs with a recommendation, not an exhaustive survey.
- **Spec-writing style (the user enforced this twice):** write what TO do, never reference rejected alternatives. No "not geometry", "instead of cataloguing", "(revised — X removed)". An implementer note must read as a clean directive, not a debate with a discarded design.

## 6. Error log
Mistakes made and corrected this session — do not reintroduce:
- **Geometry-based camera selection** (rank sensors by torch proximity, native `AVCaptureDevice`/Camera2 enumeration) was the original design and is **dead**. It was replaced wholesale by signal-based auto-detect. If you find any residual "co-located rank / nearest the flash / torchRank" wording it is stale — selection is empirical (coverage signal).
- **"Probe trigger = over-bright"** was an over-complication (needed a "normal-scene vs occlusion vs no-finger" discriminator). Dropped: the **finger-first-then-Start contract** removes the ambiguity, so detection is a one-shot round-trip on Start, no ambient trigger logic.
- **STOP marker was first placed after Phase 4** (wrong: conflated "pure-Dart executability" with "gated by the go/no-go"). Corrected to **after Phase 2** — the go/no-go gates *whether the kit is built at all*, so Phases 3–4 sit below the line even though they need no device to implement.
- Spec notes initially carried "revised —" / "supersedes" history annotations and negation phrasing; these were cleaned to positive directives (see §5).

## 7. Orientation
- **"RR" = R-R cardiac inter-beat intervals, NOT respiratory rate.** Same data type as `neiry_kit`'s `RRInterval`.
- **Two example surfaces are the SAME app at two maturity stages**, not two apps: Phase 2 = raw panels (your work, calling `flutter_ppg`/`camera` directly); Phase 9 = the same `example/` grown into a developer playground sourcing from the kit. Don't build a second app.
- **`neiry_kit/` is the sibling/template kit** (read its files by absolute path for patterns; never edit it here).
- **Filename vs title drift:** `notes/01-camera-enumeration-probe.md` is titled "Camera Auto-Detect" — the filename is a stable slug, not the current concept. Same for notes 10/11 ("...selection-bridge" files now spec a torch-only fallback).
- **Over-bright ≠ no-finger.** `over-bright` (FingerPresence) = direct flash into an uncovered lens (a finger is interfering but not on *this* lens); `absent` = no finger near the camera. Your panel must be able to tell covered / over-bright / uncovered apart — that reliability is a core spike question.

## 8. Domain model spine (settled — don't re-litigate)
- **Camera selection = signal-based auto-detect, round-trip-on-Start, finger-first contract.** User places finger on a lens+flash, presses Start; the kit runs one sequential round-trip over the rear `CameraDescription`s (probe-order = most-likely-covered first), locks the first that reads **covered** (coverage discriminator, not a confirmed pulse), else a typed `CameraPpgError` + retry. Cameras can't be opened concurrently → sequential. (notes 01, 08)
- **iOS lists every rear lens, Android lists one logical back** (confirmed from plugin sources, note 03). So the round-trip is real on iOS and degrades to default-back on Android (correct: default back = main wide at the torch). Enumeration is Dart-side via `availableCameras()`.
- **`flutter_ppg` already does the DSP** (red-channel, bandpass, peak detection, RR, SQI, SNR, finger-presence). The kit ports ONLY neiry's `_gate()` acceptance semantics later (note 12) — never `_findPeaks`/refractory/buffer. (note 12)
- **The single `example/` app is a developer playground** (stream inspector + settings), not an end-user UX. No session storyline, no aggregate result summary (mean BPM/HRV) — that's the host's job. (note 14)
- **Host contract (`mind_mobile` `ActiveRrSource`) consumes only `RrInterval {intervalMs, timestamp, isArtifact}`** with a silence window `max(2000ms, lastIntervalMs × 2)`; it does **not** read `SignalQuality`/SNR. SQI is kept on the surface as a conscious convenience (drives `MeasurementState`, host UI guidance), not a contract dependency. (note 19)
- **`warmup → measuring ⇄ poorSignal → done` lifecycle is core kit, on by default** with concrete defaults (warmup 5s, duration 60s, silence 3s, SQI floor Poor); the host renders `MeasurementState`, never reimplements the lifecycle. (note 09)
- **Phase 7 native bridges are a deletion candidate**: enumeration is Dart-side, torch runs via the `camera` plugin's `setFlashMode(FlashMode.torch)`; native code ships only as a thin `setTorch` fallback if that proves insufficient. (notes 10, 11; ROADMAP Phase 7)

## 9. Hard rules
- **Never commit without explicit user permission.** Commit messages: short noun-phrase/imperative, sentence case, no `feat:`/`fix:` prefixes, no body for single-concern commits.
- **All files in English** regardless of conversation language.
- **`flutter pub add <pkg>`** to add deps — never hand-edit `pubspec.yaml`. Use the full path `/usr/local/bin/flutter` from automation.
- **Real device only** for anything touching camera/torch — simulators/emulators have no camera or flash.
- This kit has **no proto contract** — do not add gRPC/proto here.
- Keep plugin logs minimal behind a single helper (as neiry's `nlog.dart`); the kit must not depend on `mind_mobile`'s logger.

## 10. Cross-cutting contracts / invariants checklist
- `RrInterval { int intervalMs; DateTime timestamp; bool isArtifact }` — shape-identical to neiry's `RRInterval`; the host binds both sources with one type. RR is physiologically bounded ~300–2000 ms but **no upper bound at the gate** (extreme bradycardia must survive).
- Auto-detect **locks on coverage, not pulse**; pulse confirmation is the warm-up's job after the lock.
- Selection runs **on Start** as one round-trip; on no covered sensor → typed `CameraPpgError`, return to idle, user retries. **No new `MeasurementState`** (`idle/warmup/measuring/poorSignal/done` only — no `detecting` state).
- Barrel boundary: `flutter_ppg`/`CameraImage`/`CameraController`/`PPGSignal`/`MethodChannel` types must **never** cross the public barrel; convert to kit models at the edge. (This matters when implementation starts, not for the throwaway Phase-2 panels — but keep the panels' logic portable.)
- Debug-only surface (kept out of the consumer freeze, note 19): optional `[debug]` `RrAcceptanceConfig` ctor input + `[debug]` `debugSignalStream` (`List<double>`) output. Not relevant to Phase 2 directly, but don't design them away.

## 11. Per-unit map with watch-points (the Phase-2 trio)
- **note 01 — auto-detect panel.** Became: round-trip-on-Start spec with finger-first contract; the old torch-proximity heuristic survives only as *probe order* (most-likely-covered first), never as the selection decision. Watch-point: the panel must reliably distinguish covered / over-bright / uncovered via `flutter_ppg` finger-presence — that reliability is the linchpin and a primary go/no-go input; if it flickers mid-hold, record it.
- **note 02 — flutter_ppg signal/FPS panel.** Became: raw `PPGSignal` passthrough on a deliberately minimal screen. Watch-point: record **sustained** FPS under a static screen, not nominal — heavy UI work starves frames and corrupts the signal; any animation on this panel invalidates the very number you're measuring (≥24 FPS target).
- **note 03 — device-support matrix + go/no-go (your deliverable).** Became: matrix (count, default=co-located?, auto-detect resolves?, worst-case detect time, finger-presence reliability, FPS, RR stability, verdict) + go/no-go with **item #1 = confirm rear-camera count → Phase 7 deletion decision**, then headline ship/opt-in/shelve + allow-deny list. Watch-point: iOS rows can be pre-filled from public model specs (rear-lens count) and merely confirmed; Android is structurally one back camera — confirm on 2–3 phones; state the matrix is provisional if few devices tested; the shelve/ship decision is the **user's**, you bring evidence + a recommendation.
