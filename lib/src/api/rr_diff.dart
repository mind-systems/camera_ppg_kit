/// Diffs the RR-interval window [current] (this frame's
/// `PPGSignal.rrIntervals`) against [previous] (the last frame's), returning
/// only the entries that are genuinely new.
///
/// `PPGSignal.rrIntervals` is recomputed from scratch on every frame — peaks
/// over a sliding filtered ring buffer, run through the outlier filter —
/// not an append-only log, so re-emitting the whole list every frame would
/// duplicate beats already emitted. This finds the longest overlap between
/// the tail of [previous] and the head of [current] (covering both a
/// strictly-growing window and one that has slid forward, dropping old
/// entries from the front) and returns only what follows that overlap.
///
/// This is a **minimal passthrough**, not exact dedup: it matches on raw
/// `double` values, not beat identity, so a value shifted by the outlier
/// filter re-running on a later frame can in principle be re-emitted or
/// missed. Real dedup + artifact detection lands in the Phase-6 acceptance
/// gate (note 12) — see plan 05 Phase-6 follow-ups. Kept internal to
/// `src/api/` (not exported from the barrel, so it never reaches consumers
/// through the public surface) — public within the package only so both
/// [CameraPpgSession] and the unit test can import this file directly.
List<double> diffNewIntervals(List<double> previous, List<double> current) {
  final maxOverlap = previous.length < current.length ? previous.length : current.length;

  for (var overlap = maxOverlap; overlap > 0; overlap--) {
    final previousTail = previous.sublist(previous.length - overlap);
    final currentHead = current.sublist(0, overlap);
    if (_sameIntervals(previousTail, currentHead)) {
      return current.sublist(overlap);
    }
  }
  return current;
}

bool _sameIntervals(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
