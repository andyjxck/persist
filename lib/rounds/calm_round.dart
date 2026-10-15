import 'layout.dart';
import 'round.dart';

/// A suspiciously calm round. The engine picks it (not the random draw) and
/// switches every chaos layer off for it. Sometimes it really is just calm.
class CalmType extends RoundType {
  const CalmType();
  @override
  String get id => 'calm';
  @override
  RoundFamily get family => RoundFamily.calm;
  @override
  double weight(int roundIndex) => 0; // never drawn at random
  @override
  Round create(RoundContext ctx) => CalmRound(ctx);
}

class CalmRound extends Round {
  @override
  String? demoMove() => sneaky || elapsed < 1.0 ? null : 'main';

  CalmRound(super.ctx) {
    final rng = ctx.rng;
    sneaky = rng.chance(0.3);
    final spot = randomSpot(rng);
    button = GameButton(
      id: 'main',
      colour: rng.pick(const [GameColour.blue, GameColour.green, GameColour.purple]),
      x: spot.$1,
      y: spot.$2,
    );
  }

  late final bool sneaky;
  late final GameButton button;

  @override
  String get instruction => 'Relax.';
  @override
  String get hint => sneaky ? "Don't press anything." : "Press it whenever you're ready.";
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => sneaky ? 3.0 : 6.0;
  // Calm rounds ignore the shrinking timer. That's what makes them suspicious.
  @override
  double get timeLimit => baseTime;
  @override
  bool get isCalm => true;

  @override
  void onPressDown(String? targetId) {
    if (targetId != 'main') return;
    if (sneaky) {
      fail("It said don't press anything. Calmly.");
    } else {
      succeed();
    }
  }

  @override
  void onTimeout() {
    if (sneaky) {
      succeed();
    } else {
      fail('Too relaxed.');
    }
  }
}
