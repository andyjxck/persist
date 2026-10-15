import 'package:button_panic/logic/difficulty.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Surprise TRY AGAIN', () {
    test('happens about 2% of the time', () {
      var retries = 0;
      const runs = 50000;
      for (var seed = 0; seed < runs; seed++) {
        final engine = RunEngine(mode: GameMode.endless, seed: seed);
        if (engine.registerLoss() == LossOutcome.tryAgain) retries++;
      }
      final rate = retries / runs;
      expect(Difficulty.retryChance, 0.02);
      expect(rate, closeTo(0.02, 0.003));
    });

    test('a retried round gets a shorter timer, same round otherwise', () {
      // Find a seed whose first loss turns into a TRY AGAIN.
      for (var seed = 0; seed < 10000; seed++) {
        final engine = RunEngine(mode: GameMode.endless, seed: seed);
        for (var i = 0; i < 12; i++) {
          engine.completeRound(engine.startRound());
        }
        final before = engine.startRound();
        if (engine.registerLoss() != LossOutcome.tryAgain) continue;
        final after = engine.startRound();
        expect(after.runtimeType, before.runtimeType);
        expect(after.instruction, before.instruction);
        expect(after.timeLimit, lessThan(before.timeLimit));
        expect(engine.retries, 1);
        expect(engine.score, 12, reason: 'a retry does not change the score');
        return;
      }
      fail('No seed produced a retry');
    });

    test('the retry roll is deterministic for a seed and round', () {
      final a = RunEngine(mode: GameMode.daily, seed: 777);
      final b = RunEngine(mode: GameMode.daily, seed: 777);
      expect(a.registerLoss(), b.registerLoss());
    });

    test('custom chance of 1 always retries, 0 never does', () {
      expect(RunEngine(mode: GameMode.endless, seed: 1, retryChance: 1).registerLoss(), LossOutcome.tryAgain);
      expect(RunEngine(mode: GameMode.endless, seed: 1, retryChance: 0).registerLoss(), LossOutcome.gameOver);
    });
  });

  group('Timer shrinking', () {
    test('starts at full time and never grows', () {
      expect(Difficulty.timerFactor(0), 1.0);
      for (var i = 1; i < 200; i++) {
        expect(Difficulty.timerFactor(i), lessThanOrEqualTo(Difficulty.timerFactor(i - 1)));
      }
    });

    test('gets genuinely faster early on', () {
      expect(Difficulty.timerFactor(10), lessThan(0.8));
      expect(Difficulty.timerFactor(20), lessThan(Difficulty.timerFactor(10)));
    });

    test('stops at a floor so it stays humanly possible', () {
      expect(Difficulty.timerFactor(1000), Difficulty.timerFloor);
    });

    test('each surprise retry cuts the time again', () {
      final normal = Difficulty.timerFactor(5);
      final once = Difficulty.timerFactor(5, retries: 1);
      final twice = Difficulty.timerFactor(5, retries: 2);
      expect(once, closeTo(normal * Difficulty.retryTimerMultiplier, 1e-9));
      expect(twice, lessThan(once));
    });

    test('real rounds get shorter time limits as the run goes on', () {
      final engine = RunEngine(mode: GameMode.endless, seed: 42);
      // Same round type at different points of the run -> shorter limit later.
      final early = engine.timerFactorFor(2);
      final late = engine.timerFactorFor(30);
      expect(late, lessThan(early));
    });
  });
}
