import 'layout.dart';
import 'round.dart';

// ---------------------------------------------------------------------------
// "Press the RED one" - where the labels and colours don't match.
// ---------------------------------------------------------------------------

class ColourLiarType extends RoundType {
  const ColourLiarType();
  @override
  String get id => 'colour_liar';
  @override
  RoundFamily get family => RoundFamily.liar;
  @override
  int get unlockRound => 5;
  @override
  double weight(int roundIndex) => 1.4;
  @override
  Round create(RoundContext ctx) => ColourLiarRound(ctx);
}

class ColourLiarRound extends Round {
  @override
  String? demoMove() => target.id;

  ColourLiarRound(super.ctx) {
    final rng = ctx.rng;
    final count = rng.range(2, ctx.difficulty > 0.5 ? 4 : 3);
    final fills = distinctColours(rng, count);
    // Each label names a colour that is NOT its own fill: rotate the list.
    final labels = [...fills.skip(1), fills.first];
    _buttons = [for (var i = 0; i < count; i++) GameButton(id: 'b$i', colour: fills[i], label: labels[i].name)];
    placeInSlots(_buttons, rng);

    final askedColour = rng.pick(fills);
    // Harder variant: go by the WORD, not the paint.
    bySaying = ctx.difficulty > 0.35 && rng.chance(0.4);
    if (bySaying) {
      target = _buttons.firstWhere((b) => b.label == askedColour.name);
      _text = 'Press the one that SAYS ${askedColour.name}';
    } else {
      target = _buttons.firstWhere((b) => b.colour == askedColour);
      _text = 'Press the ${askedColour.name} one';
    }
  }

  late final List<GameButton> _buttons;
  late final GameButton target;
  late final bool bySaying;
  late final String _text;

  @override
  String get instruction => _text;
  @override
  String get hint => bySaying ? 'Read the word' : 'The colour, not the word';
  @override
  List<GameButton> get buttons => _buttons;
  @override
  double get baseTime => 2.4 + 0.35 * _buttons.length;
  @override
  GameColour get rememberedColour => target.colour;

  @override
  void onPressDown(String? targetId) {
    if (targetId == null) return;
    if (targetId == target.id) {
      succeed();
    } else {
      final b = _buttons.where((b) => b.id == targetId);
      if (b.isNotEmpty) {
        fail('That was the ${b.first.colour.name} one${bySaying ? ' (it said ${b.first.label})' : ''}.');
      }
    }
  }
}

// ---------------------------------------------------------------------------
// An instruction that rewrites itself while you read it.
// ---------------------------------------------------------------------------

class RewriteType extends RoundType {
  const RewriteType();
  @override
  String get id => 'rewrite';
  @override
  RoundFamily get family => RoundFamily.liar;
  @override
  int get unlockRound => 8;
  @override
  Round create(RoundContext ctx) => RewriteRound(ctx);
}

class RewriteRound extends Round {
  @override
  String? demoMove() => _changed && elapsed > _changeAt + 0.25 && pressWanted ? 'main' : null;

  RewriteRound(super.ctx) {
    final rng = ctx.rng;
    startsAsPress = rng.chance(0.5);
    final spot = randomSpot(rng);
    button = GameButton(id: 'main', colour: rng.pick(GameColour.all), x: spot.$1, y: spot.$2);
    _changeAt = timeLimit * rng.rangeDouble(0.22, 0.42);
  }

  late final bool startsAsPress;
  late final GameButton button;
  late final double _changeAt;
  static const _glitchTime = 0.18;

  bool get _changed => elapsed >= _changeAt;
  bool get _glitching => elapsed >= _changeAt - _glitchTime && elapsed < _changeAt;

  /// What the instruction says right now.
  bool get pressWanted => _changed ? !startsAsPress : startsAsPress;

  @override
  String get instruction {
    if (_glitching) return startsAsPress ? 'PR#SS !T' : "D0N'T PR#SS";
    return pressWanted ? 'Press it' : "DON'T press it";
  }

  @override
  String get hint => _changed ? '(it changed)' : '';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 3.2;
  @override
  bool get allowSwap => false;

  @override
  void onPressDown(String? targetId) {
    if (targetId != 'main') return;
    // Judged by what the screen says at the moment you press.
    if (pressWanted && !_glitching) {
      succeed();
    } else {
      fail(
        _glitching
            ? 'You pressed while it was rewriting itself.'
            : _changed
            ? "It changed its mind. It said DON'T."
            : "It said DON'T. Then it would have said press.",
      );
    }
  }

  @override
  void onTimeout() {
    if (pressWanted) {
      fail('It changed to "Press it". You missed it.');
    } else {
      succeed();
    }
  }
}
