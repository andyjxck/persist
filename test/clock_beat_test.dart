import 'package:button_panic/logic/clock_beat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tick-tock clock', () {
    test('speeds up as the time runs out', () {
      var last = double.infinity;
      for (var f = 1.0; f >= 0; f -= 0.05) {
        final i = ClockBeat.interval(timeFraction: f, roundIndex: 3);
        expect(i, lessThanOrEqualTo(last));
        last = i;
      }
      expect(ClockBeat.interval(timeFraction: 1, roundIndex: 0), closeTo(ClockBeat.firstRound, 1e-9));
      expect(ClockBeat.interval(timeFraction: 0, roundIndex: 0), closeTo(ClockBeat.fastest, 1e-9));
    });

    test('starts each round a little faster as the run goes on, with a floor', () {
      expect(ClockBeat.roundBase(10), lessThan(ClockBeat.roundBase(0)));
      expect(ClockBeat.roundBase(40), lessThan(ClockBeat.roundBase(10)));
      expect(ClockBeat.roundBase(500), ClockBeat.lateRound);
    });

    test('never runs faster than the fastest beat', () {
      for (var r = 0; r < 200; r += 7) {
        for (var f = 0.0; f <= 1; f += 0.1) {
          expect(ClockBeat.interval(timeFraction: f, roundIndex: r), greaterThanOrEqualTo(ClockBeat.fastest));
        }
      }
    });

    test('turns tight only near the deadline of a timed round', () {
      expect(ClockBeat.tight(timeFraction: 0.9), isFalse);
      expect(ClockBeat.tight(timeFraction: 0.1), isTrue);
      expect(ClockBeat.tight(timeFraction: 0.1, timed: false), isFalse);
      expect(ClockBeat.tight(timeFraction: 0.1, calm: true), isFalse);
    });

    test('calm and untimed rounds keep a steady beat', () {
      expect(ClockBeat.interval(timeFraction: 0.1, roundIndex: 5, timed: false), ClockBeat.roundBase(5));
      expect(ClockBeat.interval(timeFraction: 0.1, roundIndex: 5, calm: true), greaterThan(ClockBeat.roundBase(5)));
    });
  });
}
