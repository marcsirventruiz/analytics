import 'package:test/test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_analytics/src/onehz/foundations/rr_window.dart';

void main() {
  const start = 1700000000;
  final ts = <double>[for (var i = 0; i < 1800; i++) (start + i) * 1000.0];
  final rr = <double>[for (var i = 0; i < 1800; i++) i.isEven ? 950 : 1050];

  test('two beats per five minutes cannot become a confident nightly HRV', () {
    final times = <double>[], values = <double>[];
    for (var w = 0; w < 12; w++) {
      times
          .addAll([(start + w * 300) * 1000.0, (start + w * 300 + 1) * 1000.0]);
      values.addAll([900, 1100]);
    }
    final m = sleepSessionWindowedRmssd(values, times,
        startSec: start, endSec: start + 3600);
    expect(m.present, isFalse);
    expect(m.confidence, 0);
  });

  test(
      'a rejected interval does not join its neighbours into a false difference',
      () {
    final values = List<double>.filled(300, 900);
    values[100] = 100; // invalid interval between two steady observed runs
    for (var i = 101; i < 300; i++) values[i] = 1000;
    final m = analyseRrWindow(values, ts.take(300).toList(),
        startMs: start * 1000.0, endMs: (start + 300) * 1000.0);
    expect(m.usable, isTrue);
    expect(m.rmssd, 0,
        reason: '900 -> 1000 across the rejected beat is not an NN pair');
  });

  test('a capture gap does not become an adjacent RMSSD pair', () {
    final times = ts.take(300).toList();
    final values = List<double>.filled(300, 1000, growable: true);
    for (var i = 80; i < 100; i++) times[i] = (start + 80) * 1000.0;
    // Separate two otherwise constant runs by a real 10-second hole.
    times.removeRange(80, 100);
    values.removeRange(80, 100);
    for (var i = 80; i < values.length; i++) values[i] = 1100;
    final m = analyseRrWindow(values, times,
        startMs: start * 1000.0, endMs: (start + 300) * 1000.0);
    expect(m.usable, isTrue);
    expect(m.rmssd, 0);
  });

  test('wake beats are excluded rather than compacted into the sleep HRV', () {
    final stages = List<String>.filled(1800, 'light');
    for (var i = 600; i < 900; i++) stages[i] = 'wake';
    final changed = List<double>.of(rr);
    for (var i = 600; i < 900; i++) changed[i] = i.isEven ? 800 : 1200;
    final m = sleepSessionWindowedRmssd(changed, ts,
        startSec: start,
        endSec: start + 1800,
        sleepTsSec: [for (var i = 0; i < 1800; i++) start + i],
        sleepStages: stages);
    expect(m.present, isTrue);
    expect(m.value, closeTo(100, 1e-8));
  });

  test('genuine large athlete HRV is not capped to match another device', () {
    final times = <double>[], values = <double>[];
    var t = start * 1000.0;
    for (var i = 0; t < (start + 1800) * 1000; i++) {
      final v = i.isEven ? 1300.0 : 1500.0;
      t += v;
      times.add((t / 1000).floor() * 1000.0);
      values.add(v);
    }
    final m = sleepSessionWindowedRmssd(values, times,
        startSec: start, endSec: start + 1800);
    expect(m.present, isTrue);
    expect(m.value, closeTo(200, 1e-8));
  });

  test(
      'night coverage counts qualified windows without double discounting their coverage',
      () {
    final times = <double>[], values = <double>[];
    for (var w = 0; w < 6; w++) {
      for (var i = 0; i < 225; i++) {
        times.add((start + w * 300 + i) * 1000.0);
        values.add(i.isEven ? 995 : 1005);
      }
    }
    // Six out of ten full windows qualify at 75% RR coverage each. Requiring
    // their SUMMED observed beat durations to cover half the entire night
    // would apply the within-window coverage gate twice (0.60 * 0.75 < 0.50).
    final m = sleepSessionWindowedRmssd(values, times,
        startSec: start, endSec: start + 3000);
    expect(m.present, isTrue);
    expect(m.value, closeTo(10, 1e-8));
    expect(m.confidence, lessThan(0.8),
        reason: 'partial coverage remains disclosed');
  });

  test('missing, reversed and mismatched timestamps abstain', () {
    for (final times in [
      <double>[],
      ts.reversed.toList(),
      [...ts]..[1] = double.nan
    ]) {
      expect(
          sleepSessionWindowedRmssd(rr, times,
                  startSec: start, endSec: start + 1800)
              .present,
          isFalse);
    }
  });

  test(
      'minimum thirty minutes uses wall-clock seconds, not surviving HR samples',
      () {
    final sparseTimes = [for (var i = 0; i < 1800; i++) start + i * 16];
    expect(
        nocturnalRhr(List<double>.filled(1800, 40), tsSec: sparseTimes).present,
        isFalse);
    final denseTimes = [for (var i = 0; i < 1800; i++) start + i];
    final m = nocturnalRhr(List<double>.filled(1800, 40), tsSec: denseTimes);
    expect(m.present, isTrue);
    expect(m.value!.low30Mean, 40);
  });
}
