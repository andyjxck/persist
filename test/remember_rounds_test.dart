import 'package:button_panic/logic/rng.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/rounds/remember_rounds.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:flutter_test/flutter_test.dart';

RoundContext _ctx(int round, int seed, List<RoundRecord> history) =>
    RoundContext(roundIndex: round, rng: SeededRng(seed), history: history, timerFactor: 1);

const _filler = RoundRecord(typeId: 'press_it', colour: GameColour.red);

void main() {
  test('Remember round shows the memo and pressing wins', () {
    for (var seed = 1; seed <= 100; seed++) {
      final r = RememberRound(_ctx(12, seed, const []));
      expect(r.instruction, contains(r.memo));
      expect(r.buttons.single.label, r.memo);
      expect(r.memoToKeep, anyOf(startsWith('n:'), startsWith('w:')));
      expect(r.allowInvert, isTrue, reason: 'memo words are never colours');
      r.onPressDown('main');
      expect(r.verdict, Verdict.success);
    }
  });

  test('Recall asks about the memo: right label wins, wrong label loses', () {
    for (var seed = 1; seed <= 200; seed++) {
      final remember = RememberRound(_ctx(12, seed, const []));
      final history = [
        RoundRecord(typeId: rememberTypeId, colour: GameColour.blue, memo: remember.memoToKeep),
        _filler,
        _filler,
      ];
      final ok = RecallRound(_ctx(15, seed + 1000, history));
      expect(ok.answer, remember.memo);
      final labels = ok.buttons.map((b) => b.label).toList();
      expect(labels.toSet().length, labels.length, reason: 'options are all different: $labels');
      expect(labels.where((l) => l == remember.memo), hasLength(1));
      ok.onPressDown(ok.correct.id);
      expect(ok.verdict, Verdict.success);

      final bad = RecallRound(_ctx(15, seed + 1000, history));
      bad.onPressDown(bad.buttons.firstWhere((b) => b.label != remember.memo).id);
      expect(bad.verdict, Verdict.fail);
      expect(bad.failReason, contains(remember.memo));
    }
  });

  test('Recall only comes after a memo, with at least two rounds between', () {
    const recall = RecallType();
    const remember = RememberType();
    const mem = RoundRecord(typeId: rememberTypeId, colour: GameColour.red, memo: 'n:47');
    const asked = RoundRecord(typeId: recallTypeId, colour: GameColour.red);
    expect(recall.isEligible(const [_filler, _filler, _filler]), isFalse);
    expect(recall.isEligible(const [mem, _filler]), isFalse);
    expect(recall.isEligible(const [mem, _filler, _filler]), isTrue);
    expect(recall.isEligible(const [mem, _filler, _filler, asked]), isFalse);
    expect(remember.isEligible(const [mem, _filler]), isFalse, reason: 'one memo at a time');
    expect(remember.isEligible(const [mem, _filler, asked]), isTrue);
  });

  test('In real runs every memo gets asked about, and the answer matches', () {
    var memos = 0;
    for (var seed = 1; seed <= 30; seed++) {
      final engine = RunEngine.endless(seed);
      String? waiting;
      for (var i = 0; i < 150; i++) {
        final r = engine.startRound();
        if (r is RememberRound) {
          expect(waiting, isNull);
          waiting = r.memo;
          memos++;
        }
        if (r is RecallRound) {
          expect(r.answer, waiting);
          waiting = null;
        }
        engine.completeRound(r);
      }
    }
    expect(memos, greaterThan(30), reason: 'remember rounds actually turn up');
  });

  test('Daily stays identical with remember rounds in the pool', () {
    List<String> play(RunEngine e) => [
      for (var i = 0; i < 120; i++)
        () {
          final r = e.startRound();
          final s = '${e.typeFor(i).id}/${r.instruction}/${r.buttons.map((b) => b.label).join(',')}';
          e.completeRound(r);
          return s;
        }(),
    ];
    final a = play(RunEngine.daily(DateTime(2026, 10, 16, 9)));
    final b = play(RunEngine.daily(DateTime(2026, 10, 16, 22)));
    expect(a, b);
    expect(a.any((s) => s.startsWith(recallTypeId)), isTrue);
  });
}
