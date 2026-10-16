import 'dart:math' as math;
import '../util.dart';

/// Observed, timestamp-aware RR window. Thresholds are conservative signal
/// quality rules, not a validated diagnostic classifier or a WHOOP formula.
class RrWindowStats {
  final List<double> beats;
  final double? rmssd;
  final double coveredMs;
  final int pairs;
  const RrWindowStats(this.beats, this.rmssd, this.coveredMs, this.pairs);
  static const absent = RrWindowStats([], null, 0, 0);
  bool get usable => rmssd != null;
}

/// Analyse one real wall-clock window in an ordered, second-quantized RR stream.
/// Rejected beats and missing runs BREAK successive pairs; they are never
/// compacted into artificial neighbours. Same-second beats remain supported.
RrWindowStats analyseRrWindow(
  List<double> rr,
  List<double> ts, {
  required double startMs,
  required double endMs,
  double minCoverage = 0.7,
  double maxArtifactFraction = 0.2,
  int minPairs = 30,
}) {
  if (rr.length != ts.length ||
      rr.isEmpty ||
      !startMs.isFinite ||
      !endMs.isFinite ||
      endMs <= startMs) return RrWindowStats.absent;
  int lowerBound(double value) {
    var lo = 0, hi = ts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (ts[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  final lo = lowerBound(startMs), hi = lowerBound(endMs);
  if (hi - lo < minPairs + 1) return RrWindowStats.absent;
  bool plausible(double v) => v.isFinite && v >= 300 && v <= 2000;
  final clean = List<bool>.filled(hi - lo, false);
  final beats = <double>[];
  for (var i = lo; i < hi; i++) {
    if (!ts[i].isFinite ||
        ts[i] < startMs ||
        ts[i] >= endMs ||
        (i > lo && ts[i] < ts[i - 1])) return RrWindowStats.absent;
    if (!plausible(rr[i])) continue;
    final neighbours = <double>[];
    for (var j = math.max(lo, i - 2); j < math.min(hi, i + 3); j++) {
      if (j != i && plausible(rr[j])) neighbours.add(rr[j]);
    }
    final med = median(neighbours);
    if (med != null && (rr[i] - med).abs() > med * 0.20) continue;
    clean[i - lo] = true;
    beats.add(rr[i]);
  }
  if (1 - beats.length / (hi - lo) > maxArtifactFraction)
    return RrWindowStats.absent;
  var sumSq = 0.0, covered = 0.0;
  var pairs = 0;
  for (var i = lo + 1; i < hi; i++) {
    if (!clean[i - lo] || !clean[i - lo - 1]) continue;
    // Device anchors are whole seconds, so allow ONE second of quantization,
    // not an arbitrary multi-second/multi-minute hole between two beats.
    final gap = ts[i] - ts[i - 1];
    if (gap < 0 || gap > math.max(rr[i], rr[i - 1]) + 1000) continue;
    final delta = rr[i] - rr[i - 1];
    sumSq += delta * delta;
    covered += rr[i];
    pairs++;
  }
  final duration = endMs - startMs;
  // Grossly excessive beat duration also indicates duplicates/corrupt timing.
  if (pairs < minPairs ||
      covered < duration * minCoverage ||
      covered > duration * 1.1) return RrWindowStats.absent;
  return RrWindowStats(
      beats, math.sqrt(sumSq / pairs), math.min(covered, duration), pairs);
}
