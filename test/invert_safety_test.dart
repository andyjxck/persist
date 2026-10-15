import 'package:button_panic/logic/rng.dart';
import 'package:button_panic/rounds/liar_rounds.dart';
import 'package:button_panic/rounds/memory_rounds.dart';
import 'package:button_panic/rounds/registry.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:flutter_test/flutter_test.dart';

const _history = [
  RoundRecord(typeId: 'press_it', colour: GameColour.red),
  RoundRecord(typeId: 'press_it', colour: GameColour.green),
  RoundRecord(typeId: 'press_it', colour: GameColour.purple),
  RoundRecord(typeId: 'press_it', colour: GameColour.orange),
];

RoundContext _ctx(int round, int seed, PlayPlatform platform) => RoundContext(
      roundIndex: round,
      rng: SeededRng(seed),
      history: _history,
      timerFactor: 1,
      platform: platform,
    );

void main() {
  test('"What colour was the button N rounds ago" never allows invert', () {
    for (var seed = 1; seed <= 200; seed++) {
      final r = RoundsAgoRound(_ctx(10, seed, PlayPlatform.touch));
      expect(r.allowInvert, isFalse, reason: r.instruction);
    }
  });

  test('Colour liar rounds never allow invert', () {
    for (var seed = 1; seed <= 200; seed++) {
      final r = ColourLiarRound(_ctx(20, seed, PlayPlatform.touch));
      expect(r.allowInvert, isFalse, reason: r.instruction);
    }
  });

  test('No round whose instruction names a colour allows invert', () {
    final words = [...GameColour.all.map((c) => c.name.toLowerCase()), 'colour', 'color'];
    for (final platform in PlayPlatform.values) {
      for (final type in roundTypesFor(platform)) {
        if (!type.isEligible(_history)) continue;
        for (var seed = 1; seed <= 40; seed++) {
          final r = type.create(_ctx(15, seed, platform));
          final text = r.instruction.toLowerCase();
          if (words.any(text.contains)) {
            expect(r.allowInvert, isFalse, reason: '${type.runtimeType}: ${r.instruction}');
          }
        }
      }
    }
  });
}
