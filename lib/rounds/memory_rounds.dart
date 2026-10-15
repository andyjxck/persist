import 'layout.dart';
import 'round.dart';

// ---------------------------------------------------------------------------
// "Which colour was the button two rounds ago?"
// ---------------------------------------------------------------------------

class RoundsAgoType extends RoundType {
  const RoundsAgoType();
  @override
  String get id => 'rounds_ago';
  @override
  RoundFamily get family => RoundFamily.memory;
  @override
  int get unlockRound => 6;
  @override
  double weight(int roundIndex) => 1.2;
  @override
  bool isEligible(List<RoundRecord> history) => history.length >= 2;
  @override
  Round create(RoundContext ctx) => RoundsAgoRound(ctx);
}

class RoundsAgoRound extends Round {
  @override
  String? demoMove() => _buttons.firstWhere((b) => b.colour == answer).id;

  RoundsAgoRound(super.ctx) {
    final rng = ctx.rng;
    final history = ctx.history;
    // Usually two rounds back; sometimes one, later sometimes three.
    final options = <int>[2, 2, 1, if (history.length >= 3 && ctx.difficulty > 0.4) 3];
    roundsBack = rng.pick(options);
    answer = history[history.length - roundsBack].colour;

    final count = ctx.difficulty > 0.5 ? 4 : 3;
    final others = GameColour.all.where((c) => c != answer).toList();
    final colours = [answer, ...rng.shuffled(others).take(count - 1)];
    _buttons = [for (var i = 0; i < colours.length; i++) GameButton(id: 'c$i', colour: colours[i])];
    placeInSlots(_buttons, rng);
  }

  late final int roundsBack;
  late final GameColour answer;
  late final List<GameButton> _buttons;

  @override
  String get instruction => switch (roundsBack) {
    1 => 'What colour was the button LAST round?',
    2 => 'What colour was the button TWO rounds ago?',
    _ => 'What colour was it THREE rounds ago?',
  };
  @override
  List<GameButton> get buttons => _buttons;
  @override
  double get baseTime => 3.6;
  @override
  GameColour get rememberedColour => answer;

  @override
  void onPressDown(String? targetId) {
    if (targetId == null) return;
    final b = _buttons.where((b) => b.id == targetId);
    if (b.isEmpty) return;
    if (b.first.colour == answer) {
      succeed();
    } else {
      fail('It was ${answer.name}.');
    }
  }
}

// ---------------------------------------------------------------------------
// Repeat a flash sequence.
// ---------------------------------------------------------------------------

class FlashSequenceType extends RoundType {
  const FlashSequenceType();
  @override
  String get id => 'flash_sequence';
  @override
  RoundFamily get family => RoundFamily.memory;
  @override
  int get unlockRound => 13;
  @override
  Round create(RoundContext ctx) => FlashSequenceRound(ctx);
}

class FlashSequenceRound extends Round {
  @override
  String? demoMove() => showing || inputIndex >= sequence.length ? null : _buttons[sequence[inputIndex]].id;

  FlashSequenceRound(super.ctx) {
    final rng = ctx.rng;
    const colours = [GameColour.red, GameColour.blue, GameColour.green, GameColour.yellow];
    _buttons = [for (var i = 0; i < 4; i++) GameButton(id: 'f$i', colour: colours[i])];
    placeInSlots(_buttons, rng);
    final length = (3 + ctx.difficulty * 3).round().clamp(3, 6);
    sequence = [for (var i = 0; i < length; i++) rng.nextInt(4)];
    // Flashes speed up as the run goes on.
    flashOn = (0.45 - ctx.difficulty * 0.15).clamp(0.25, 0.45);
  }

  late final List<GameButton> _buttons;
  late final List<int> sequence;
  late final double flashOn;
  static const flashGap = 0.15;
  int inputIndex = 0;

  double get showDuration => 0.4 + sequence.length * (flashOn + flashGap);
  bool get showing => elapsed < showDuration;

  @override
  String get instruction => showing ? 'Watch...' : 'Repeat it!';
  @override
  String get hint => showing ? '' : '$inputIndex/${sequence.length}';
  @override
  List<GameButton> get buttons => _buttons;
  @override
  double get baseTime => 1.2 + 0.7 * sequence.length;
  // Watching time is never squeezed; only your answering time is.
  @override
  double get timeLimit => showDuration + baseTime * ctx.timerFactor;
  @override
  bool get allowSwap => false;
  @override
  GameColour get rememberedColour => _buttons[sequence.last].colour;

  @override
  void tick(double dt) {
    for (final b in _buttons) {
      b.highlighted = false;
    }
    if (showing) {
      final t = elapsed - 0.4;
      if (t >= 0) {
        final step = (t / (flashOn + flashGap)).floor();
        final within = t - step * (flashOn + flashGap);
        if (step < sequence.length && within < flashOn) {
          _buttons[sequence[step]].highlighted = true;
        }
      }
    }
  }

  @override
  void onPressDown(String? targetId) {
    if (showing || targetId == null) return;
    final index = _buttons.indexWhere((b) => b.id == targetId);
    if (index < 0) return;
    if (index == sequence[inputIndex]) {
      inputIndex++;
      if (inputIndex >= sequence.length) succeed();
    } else {
      final names = sequence.map((i) => _buttons[i].colour.name).join(', ');
      fail('Wrong order. It was $names.');
    }
  }

  @override
  void onTimeout() => fail('Too slow. Got $inputIndex of ${sequence.length}.');
}
