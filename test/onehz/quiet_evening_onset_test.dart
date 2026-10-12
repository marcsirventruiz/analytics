import 'package:test/test.dart';
import 'package:openstrap_analytics/onehz.dart';

void main() {
  const start = 100000;
  List<HrTs> data({bool fall = true}) => [
        for (var i = 0; i < 8 * 3600; i++)
          HrTs(start + i, fall && i >= 90 * 60 ? 52 : 56)
      ];
  const prelude = [
    StageSegment(start, start + 20 * 60, 'light'),
    StageSegment(start + 20 * 60, start + 45 * 60, 'rem')
  ];
  test('quiet REM-heavy prelude tightens at sustained observed HR decline', () {
    expect(
        quietEveningOnset(
            startSec: start,
            endSec: start + 8 * 3600,
            hr: data(),
            stages: prelude),
        start + 90 * 60);
  });
  test('missing data, no fall and normal deep-led onset never move a boundary',
      () {
    for (final input in [<HrTs>[], data(fall: false)]) {
      expect(
          quietEveningOnset(
              startSec: start,
              endSec: start + 8 * 3600,
              hr: input,
              stages: prelude),
          start);
    }
    expect(
        quietEveningOnset(
            startSec: start,
            endSec: start + 8 * 3600,
            hr: data(),
            stages: const [StageSegment(start, start + 45 * 60, 'deep')]),
        start);
  });
  test('short sessions are unchanged', () {
    expect(
        quietEveningOnset(
            startSec: start,
            endSec: start + 3 * 3600,
            hr: data(),
            stages: prelude),
        start);
  });
  test('a lower HR beyond a missing initial window is not onset evidence', () {
    expect(
        quietEveningOnset(
            startSec: start,
            endSec: start + 8 * 3600,
            hr: data().where((s) => s.ts >= start + 46 * 60).toList(),
            stages: prelude),
        start);
  });
  test('a deep-led late bedtime is retained even if HR falls later', () {
    expect(
        quietEveningOnset(
            startSec: start,
            endSec: start + 8 * 3600,
            hr: data(),
            stages: const [
              StageSegment(start, start + 20 * 60, 'light'),
              StageSegment(start + 20 * 60, start + 45 * 60, 'deep')
            ]),
        start);
  });
}
