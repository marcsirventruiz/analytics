// Read-only diagnostic: inputs are canonical RR JSON, onset and offset seconds.
// No personal data is included. Run from this package's checkout.
import 'dart:convert';
import 'dart:io';
import '../lib/src/onehz/clinical/hrv_time.dart';
import '../lib/src/onehz/foundations/rr_window.dart';

void main(List<String> args) {
  final rows =
      (jsonDecode(File(args[0]).readAsStringSync()) as List).cast<Map>();
  final rr = [for (final r in rows) (r['rr_ms'] as num).toDouble()];
  final ts = [for (final r in rows) (r['rr_ts_ms'] as num).toDouble()];
  final start = int.parse(args[1]), end = int.parse(args[2]);
  for (var from = start; from + 300 <= end; from += 300) {
    final m = analyseRrWindow(rr, ts,
        startMs: from * 1000.0, endMs: (from + 300) * 1000.0);
    // Compare passing windows with raw timing/beat coverage, not a target HRV.
    final values = [
      for (var i = 0; i < rr.length; i++)
        if (ts[i] >= from * 1000 && ts[i] < (from + 300) * 1000) rr[i]
    ];
    print(jsonEncode({
      'window': (from - start) ~/ 300,
      'usable': m.usable,
      'raw_beats': values.length,
      'raw_seconds': values.fold(0.0, (a, b) => a + b) / 1000,
      'pairs': m.pairs,
      'covered_seconds': m.coveredMs / 1000,
      'rmssd': m.rmssd
    }));
  }
  print(
      sleepSessionWindowedRmssd(rr, ts, startSec: start, endSec: end).toJson());
}
