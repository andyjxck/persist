import 'layout.dart';
import 'round.dart';

// ---------------------------------------------------------------------------
// "Press it"
// ---------------------------------------------------------------------------

class PressItType extends RoundType {
  const PressItType();
  @override
  String get id => 'press_it';
  @override
  RoundFamily get family => RoundFamily.simple;
  @override
  double weight(int roundIndex) => roundIndex < 6 ? 3 : 1.2;
  @override
  Round create(RoundContext ctx) => PressItRound(ctx);
}

class PressItRound extends Round {
  @override
  String? demoMove() => 'main';

  PressItRound(super.ctx) {
    final rng = ctx.rng;
    final spot = randomSpot(rng);
    // Later on, the label starts lying ("NO", "DON'T") to rattle you.
    final liarLabel = ctx.difficulty > 0.2 && rng.chance(0.35);
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      label: liarLabel ? rng.pick(const ['NO', "DON'T", 'STOP', 'NOPE']) : '',
      x: spot.$1,
      y: spot.$2,
    );
    _text = rng.pick(const ['Press it', 'PRESS IT', 'Tap the button', 'Press it. Now.']);
  }

  late final GameButton button;
  late final String _text;

  @override
  String get instruction => _text;
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 2.4;

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') succeed();
  }
}

// ---------------------------------------------------------------------------
// "DON'T press it"
// ---------------------------------------------------------------------------

class DontPressType extends RoundType {
  const DontPressType();
  @override
  String get id => 'dont_press';
  @override
  RoundFamily get family => RoundFamily.simple;
  @override
  int get unlockRound => 1;
  @override
  double weight(int roundIndex) => roundIndex < 6 ? 2 : 1;
  @override
  Round create(RoundContext ctx) => DontPressRound(ctx);
}

class DontPressRound extends Round {
  @override
  String? demoMove() => null;

  DontPressRound(super.ctx) {
    final rng = ctx.rng;
    final spot = randomSpot(rng);
    final temptingLabel = ctx.difficulty > 0.15 && rng.chance(0.5);
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      label: temptingLabel ? rng.pick(const ['PRESS ME', 'GO', 'TAP!', 'YES']) : '',
      x: spot.$1,
      y: spot.$2,
    );
    _text = rng.pick(const ["DON'T press it", 'Do NOT press it', 'Leave it alone', 'Hands off']);
  }

  late final GameButton button;
  late final String _text;

  @override
  String get instruction => _text;
  @override
  String get hint => 'Wait for the timer';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 2.0;

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') fail("You pressed it. It said don't.");
  }

  @override
  void onTimeout() => succeed();
}

// ---------------------------------------------------------------------------
// "Press it 3 times"
// ---------------------------------------------------------------------------

class PressNTimesType extends RoundType {
  const PressNTimesType();
  @override
  String get id => 'press_n_times';
  @override
  RoundFamily get family => RoundFamily.simple;
  @override
  int get unlockRound => 2;
  @override
  Round create(RoundContext ctx) => PressNTimesRound(ctx);
}

class PressNTimesRound extends Round {
  @override
  String? demoMove() => 'main';

  PressNTimesRound(super.ctx) {
    final rng = ctx.rng;
    target = rng.range(2, (3 + (ctx.difficulty * 4).round()).clamp(3, 7));
    final spot = randomSpot(rng);
    button = GameButton(id: 'main', colour: rng.pick(GameColour.all), label: '$target', x: spot.$1, y: spot.$2);
  }

  late final int target;
  late final GameButton button;
  int count = 0;

  static const _words = ['', 'once', 'twice', '3 times', '4 times', '5 times', '6 times', '7 times'];

  @override
  String get instruction => 'Press it ${_words[target]}';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 1.4 + 0.45 * target;

  @override
  void onPressDown(String? targetId) {
    if (targetId != 'main') return;
    count++;
    button.label = '${target - count}';
    if (count >= target) succeed();
  }

  @override
  void onTimeout() => fail('Only $count of $target presses.');
}

// ---------------------------------------------------------------------------
// "Hold it"
// ---------------------------------------------------------------------------

class HoldItType extends RoundType {
  const HoldItType();
  @override
  String get id => 'hold_it';
  @override
  RoundFamily get family => RoundFamily.simple;
  @override
  int get unlockRound => 2;
  @override
  Round create(RoundContext ctx) => HoldItRound(ctx);
}

class HoldItRound extends Round {
  @override
  String? demoMove() => holding ? null : 'hold:main';

  HoldItRound(super.ctx) {
    final rng = ctx.rng;
    holdTime = rng.rangeDouble(0.9, 1.4 + ctx.difficulty * 0.6);
    final spot = randomSpot(rng);
    button = GameButton(id: 'main', colour: rng.pick(GameColour.all), label: 'HOLD', x: spot.$1, y: spot.$2);
  }

  late final double holdTime;
  late final GameButton button;
  double held = 0;
  bool holding = false;

  /// 0..1, drawn as a ring around the button.
  double get progress => (held / holdTime).clamp(0, 1);

  @override
  String get instruction => 'Hold it';
  @override
  String get hint => holding ? 'Keep holding...' : 'Press and keep your finger on it';
  @override
  List<GameButton> get buttons => [button];
  // Holding time is never squeezed below what the hold itself needs.
  @override
  double get timeLimit => holdTime + 1.6 * ctx.timerFactor;
  @override
  double get baseTime => holdTime + 1.6;

  @override
  void tick(double dt) {
    if (holding) {
      held += dt;
      button.ring = progress;
      if (held >= holdTime) succeed();
    }
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') holding = true;
  }

  @override
  void onPressUp(String? targetId) {
    if (targetId == 'main' && holding && held < holdTime) {
      fail('You let go too early.');
    }
  }

  @override
  void onTimeout() => fail(holding ? 'Not held long enough.' : 'You never held it.');
}
