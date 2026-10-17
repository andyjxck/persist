import 'package:button_panic/logic/difficulty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chaos ramps up early and stacks', () {
    test('the first three rounds are clean, so you can learn the game', () {
      for (var seed = 0; seed < 200; seed++) {
        for (var n = 0; n < 3; n++) {
          expect(ChaosState.forRound(seed, n).activeLayers, isEmpty, reason: 'seed $seed round $n');
        }
      }
    });

    test('drift and blackouts show up, and only after their round', () {
      var drift = 0, blackout = 0;
      for (var seed = 0; seed < 300; seed++) {
        for (var n = 0; n < 30; n++) {
          final c = ChaosState.forRound(seed, n);
          if (c.drift > 0) {
            drift++;
            expect(n, greaterThanOrEqualTo(6));
          }
          if (c.blackouts > 0) {
            blackout++;
            expect(n, greaterThanOrEqualTo(9));
            expect(c.blackouts, lessThanOrEqualTo(2));
          }
        }
      }
      expect(drift, greaterThan(300));
      expect(blackout, greaterThan(300));
    });

    test('by round 15 the average round stacks at least two chaos layers', () {
      var layers = 0, rounds = 0;
      for (var seed = 0; seed < 300; seed++) {
        final c = ChaosState.forRound(seed, 15);
        if (c.calm) continue;
        layers += c.activeLayers.length;
        rounds++;
      }
      expect(layers / rounds, greaterThanOrEqualTo(2));
    });

    test('the same seed and round always give the same chaos (Daily stays fair)', () {
      for (var n = 0; n < 40; n++) {
        expect(ChaosState.forRound(42, n).activeLayers, ChaosState.forRound(42, n).activeLayers);
        expect(ChaosState.forRound(42, n).drift, ChaosState.forRound(42, n).drift);
      }
    });
  });
}
