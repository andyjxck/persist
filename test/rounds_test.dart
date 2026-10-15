import 'package:button_panic/logic/rng.dart';
import 'package:button_panic/rounds/calm_round.dart';
import 'package:button_panic/rounds/fake_rounds.dart';
import 'package:button_panic/rounds/liar_rounds.dart';
import 'package:button_panic/rounds/memory_rounds.dart';
import 'package:button_panic/rounds/registry.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:button_panic/rounds/runner_rounds.dart';
import 'package:button_panic/rounds/simple_rounds.dart';
import 'package:flutter_test/flutter_test.dart';

RoundContext ctx({int round = 0, int seed = 1, List<RoundRecord>? history}) =>
    RoundContext(roundIndex: round, rng: SeededRng(seed), history: history ?? const [], timerFactor: 1);

void run(Round r, double seconds) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds && r.verdict == Verdict.pending; t += dt) {
    r.update(dt);
  }
}

void main() {
  test('Press it: pressing wins, waiting loses', () {
    final a = PressItRound(ctx())..onPressDown('main');
    expect(a.verdict, Verdict.success);
    final b = PressItRound(ctx());
    run(b, 10);
    expect(b.verdict, Verdict.fail);
  });

  test("DON'T press it: waiting wins, pressing loses", () {
    final a = DontPressRound(ctx());
    run(a, 10);
    expect(a.verdict, Verdict.success);
    final b = DontPressRound(ctx())..onPressDown('main');
    expect(b.verdict, Verdict.fail);
  });

  test('Press it N times needs exactly N presses', () {
    final r = PressNTimesRound(ctx());
    for (var i = 0; i < r.target - 1; i++) {
      r.onPressDown('main');
    }
    expect(r.verdict, Verdict.pending);
    r.onPressDown('main');
    expect(r.verdict, Verdict.success);
  });

  test('Hold it: letting go early loses, holding long enough wins', () {
    final a = HoldItRound(ctx())..onPressDown('main');
    run(a, 0.3);
    a.onPressUp('main');
    expect(a.verdict, Verdict.fail);
    final b = HoldItRound(ctx())..onPressDown('main');
    run(b, 5);
    expect(b.verdict, Verdict.success);
  });

  test('Colour liar: labels never match their colour', () {
    for (var seed = 0; seed < 50; seed++) {
      final r = ColourLiarRound(ctx(seed: seed, round: 30));
      for (final b in r.buttons) {
        expect(b.label, isNot(b.colour.name));
      }
      r.onPressDown(r.target.id);
      expect(r.verdict, Verdict.success);
    }
  });

  test('Memory: asks about the right past round', () {
    final history = [
      const RoundRecord(typeId: 'press_it', colour: GameColour.green),
      const RoundRecord(typeId: 'press_it', colour: GameColour.purple),
      const RoundRecord(typeId: 'press_it', colour: GameColour.orange),
    ];
    final r = RoundsAgoRound(ctx(history: history, round: 3));
    final expected = history[history.length - r.roundsBack].colour;
    expect(r.answer, expected);
    final right = r.buttons.firstWhere((b) => b.colour == expected);
    r.onPressDown(right.id);
    expect(r.verdict, Verdict.success);
  });

  test('Flash sequence: repeating it in order wins', () {
    final r = FlashSequenceRound(ctx(round: 20));
    run(r, r.showDuration + 0.01);
    for (final i in r.sequence) {
      r.onPressDown(r.buttons[i].id);
    }
    expect(r.verdict, Verdict.success);
  });

  test('Decoys: pressing a decoy loses', () {
    final r = DecoyRound(ctx(round: 20));
    run(r, r.shuffleEnd);
    r.onPressDown(r.buttons.last.id);
    expect(r.verdict, Verdict.fail);
  });

  test('Fake win: tapping the prize loses', () {
    final r = FakeWinRound(ctx(round: 20));
    run(r, 0.5);
    expect(r.overlays, isNotEmpty);
    r.onPressDown('prize');
    expect(r.verdict, Verdict.fail);
  });

  test('Calm rounds ignore the shrinking timer', () {
    final r = CalmRound(RoundContext(roundIndex: 50, rng: SeededRng(3), history: const [], timerFactor: 0.45));
    expect(r.timeLimit, r.baseTime);
  });

  test('Every registered type builds a valid round at any stage', () {
    final history = [for (var i = 0; i < 5; i++) RoundRecord(typeId: 'x', colour: GameColour.all[i])];
    for (final type in [...allRoundTypes, calmRoundType]) {
      for (final round in [0, 10, 40, 80]) {
        final r = type.create(ctx(round: round, history: history, seed: round + 7));
        expect(r.buttons, isNotEmpty, reason: type.id);
        expect(r.instruction, isNotEmpty, reason: type.id);
        expect(r.timeLimit, greaterThan(0.5), reason: type.id);
        run(r, 30);
        expect(r.verdict, isNot(Verdict.pending), reason: '${type.id} must end');
      }
    }
    expect({for (final t in allRoundTypes) t.id}.length, allRoundTypes.length, reason: 'ids are unique');
  });

  test('Rewrite and runners exist in the registry', () {
    expect(allRoundTypes.whereType<RewriteType>(), isNotEmpty);
    expect(allRoundTypes.whereType<DodgerType>(), isNotEmpty);
    expect(allRoundTypes.whereType<FakeNotificationType>(), isNotEmpty);
  });
}
