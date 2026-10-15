import 'package:button_panic/logic/rng.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plays [rounds] rounds by "surviving" each one and records what came up.
List<String> playSequence(RunEngine engine, int rounds) {
  final seen = <String>[];
  for (var i = 0; i < rounds; i++) {
    final r = engine.startRound();
    final layout = r.buttons
        .map((b) => '${b.colour.name}@${b.x.toStringAsFixed(3)},${b.y.toStringAsFixed(3)}:${b.label}')
        .join('|');
    seen.add('${engine.typeFor(i).id}/${r.instruction}/$layout/${r.timeLimit.toStringAsFixed(4)}');
    engine.completeRound(r);
  }
  return seen;
}

void main() {
  group('Seeded Daily run', () {
    test('same date gives the exact same sequence of rounds', () {
      final a = playSequence(RunEngine.daily(DateTime(2026, 10, 15, 8, 0)), 60);
      final b = playSequence(RunEngine.daily(DateTime(2026, 10, 15, 23, 59)), 60);
      expect(a, equals(b));
    });

    test('different dates give different sequences', () {
      final a = playSequence(RunEngine.daily(DateTime(2026, 10, 15)), 30);
      final b = playSequence(RunEngine.daily(DateTime(2026, 10, 16)), 30);
      expect(a, isNot(equals(b)));
    });

    test('daily seed only depends on the calendar day', () {
      expect(dailySeed(DateTime(2026, 1, 2, 0, 1)), dailySeed(DateTime(2026, 1, 2, 23, 0)));
      expect(dailySeed(DateTime(2026, 1, 2)), isNot(dailySeed(DateTime(2026, 1, 3))));
    });

    test('the generator is pinned (guards against accidental changes)', () {
      // If these numbers change, every past Daily run changes too.
      final rng = SeededRng(12345);
      final values = [for (var i = 0; i < 5; i++) rng.nextUint32()];
      expect(values, [4207900869, 1317490944, 2079646450, 3513001552, 2187978186]);
      expect(hashString('button-panic'), 875917071);
    });

    test('generator output is evenly spread', () {
      final rng = SeededRng(99);
      final buckets = List.filled(10, 0);
      for (var i = 0; i < 100000; i++) {
        buckets[(rng.nextDouble() * 10).floor()]++;
      }
      for (final b in buckets) {
        expect(b, inInclusiveRange(9500, 10500));
      }
    });

    test('new round families unlock as the run goes on', () {
      final engine = RunEngine.daily(DateTime(2026, 10, 15));
      final early = {for (var i = 0; i < 4; i++) engine.typeFor(i).family};
      expect(early, everyElement(anyOf(RoundFamily.simple, RoundFamily.calm)));
      final families = <RoundFamily>{};
      final seen = playSequence(engine, 200);
      expect(seen, hasLength(200));
      for (var i = 0; i < 200; i++) {
        families.add(engine.typeFor(i).family);
      }
      expect(families, containsAll(RoundFamily.values));
    });
  });
}
