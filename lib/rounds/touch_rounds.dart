import 'dart:math' as math;

import 'round.dart';

// Rounds that only exist in the mobile version: flicks, two thumbs at once,
// and rubbing the screen.

// ---------------------------------------------------------------------------
// Flick it in a direction (a tap doesn't count).
// ---------------------------------------------------------------------------

class FlickType extends RoundType {
  const FlickType();
  @override
  String get id => 'flick';
  @override
  RoundFamily get family => RoundFamily.touch;
  @override
  int get unlockRound => 4;
  @override
  double weight(int roundIndex) => 1.2;
  @override
  Round create(RoundContext ctx) => FlickRound(ctx);
}

class FlickRound extends Round {
  FlickRound(super.ctx) {
    final rng = ctx.rng;
    dir = rng.pick(const ['UP', 'DOWN', 'LEFT', 'RIGHT']);
    // Later, the arrow on the button lies.
    final liar = ctx.difficulty > 0.3 && rng.chance(0.4);
    final shown = liar ? rng.pick(const ['UP', 'DOWN', 'LEFT', 'RIGHT'].where((d) => d != dir).toList()) : dir;
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      label: _arrow[shown]!,
      x: 0.5,
      y: rng.rangeDouble(0.45, 0.6),
      radius: 0.2,
    );
  }

  static const _arrow = {'UP': '\u2191', 'DOWN': '\u2193', 'LEFT': '\u2190', 'RIGHT': '\u2192'};

  late final String dir;
  late final GameButton button;
  bool _down = false;
  double _dx = 0, _dy = 0;

  @override
  String get instruction => 'Flick it $dir';
  @override
  String get hint => 'Swipe, don\'t tap';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 2.6;
  @override
  bool get allowSwap => false;

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') {
      _down = true;
      _dx = _dy = 0;
    }
  }

  @override
  void onDrag(String? targetId, double dx, double dy) {
    if (!_down || targetId != 'main') return;
    _dx = dx;
    _dy = dy;
    // The button follows the finger a little, on a rubber band.
    final d = math.sqrt(dx * dx + dy * dy);
    final k = d == 0 ? 0.0 : (0.12 * (1 - math.exp(-d * 6))) / d;
    button
      ..dragX = dx * k
      ..dragY = dy * k;
  }

  @override
  void onPressUp(String? targetId) {
    if (!_down || targetId != 'main') return;
    _down = false;
    button.dragX = button.dragY = 0;
    final d = math.sqrt(_dx * _dx + _dy * _dy);
    if (d < 0.08) {
      fail('That was a tap. It said flick.');
      return;
    }
    final got = _dx.abs() > _dy.abs() ? (_dx > 0 ? 'RIGHT' : 'LEFT') : (_dy > 0 ? 'DOWN' : 'UP');
    if (got == dir) {
      succeed();
    } else {
      fail('You flicked it $got. It said $dir.');
    }
  }

  @override
  void onTimeout() => fail('It never moved.');

  @override
  String? demoMove() {
    final v = switch (dir) {
      'UP' => '0:-0.3',
      'DOWN' => '0:0.3',
      'LEFT' => '-0.3:0',
      _ => '0.3:0',
    };
    return 'swipe:main:$v';
  }
}

// ---------------------------------------------------------------------------
// Two thumbs: hold both buttons at once.
// ---------------------------------------------------------------------------

class BothThumbsType extends RoundType {
  const BothThumbsType();
  @override
  String get id => 'both_thumbs';
  @override
  RoundFamily get family => RoundFamily.touch;
  @override
  int get unlockRound => 6;
  @override
  Round create(RoundContext ctx) => BothThumbsRound(ctx);
}

class BothThumbsRound extends Round {
  BothThumbsRound(super.ctx) {
    final rng = ctx.rng;
    need = rng.rangeDouble(0.9, 1.3 + ctx.difficulty * 0.5);
    final cs = rng.shuffled(GameColour.all).take(2).toList();
    // Where thumbs naturally rest: low on the screen, near each side.
    final y = rng.rangeDouble(0.7, 0.82);
    left = GameButton(id: 'left', colour: cs[0], label: 'HOLD', x: 0.24, y: y, radius: 0.17);
    right = GameButton(id: 'right', colour: cs[1], label: 'HOLD', x: 0.76, y: y, radius: 0.17);
  }

  late final double need;
  late final GameButton left;
  late final GameButton right;
  double held = 0;
  bool _l = false, _r = false;

  @override
  String get instruction => 'Hold BOTH at once';
  @override
  String get hint => (_l && _r) ? 'Keep holding...' : 'Use two thumbs';
  @override
  List<GameButton> get buttons => [left, right];
  @override
  double get timeLimit => need + 2.2 * ctx.timerFactor;
  @override
  double get baseTime => need + 2.2;
  @override
  bool get allowSwap => false;

  @override
  void tick(double dt) {
    if (_l && _r) {
      held += dt;
      left.ring = right.ring = (held / need).clamp(0, 1);
      if (held >= need) succeed();
    }
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'left') _l = true;
    if (targetId == 'right') _r = true;
  }

  @override
  void onPressUp(String? targetId) {
    final wasBoth = _l && _r;
    if (targetId == 'left') _l = false;
    if (targetId == 'right') _r = false;
    if (wasBoth && held < need) fail('You let go too early.');
  }

  @override
  void onTimeout() => fail(held > 0 ? 'Not held long enough.' : 'Both. At the same time.');

  @override
  String? demoMove() => (_l && _r) ? null : 'hold:left,right';
}

// ---------------------------------------------------------------------------
// Rub it clean: scrub back and forth on the button.
// ---------------------------------------------------------------------------

class ScratchType extends RoundType {
  const ScratchType();
  @override
  String get id => 'scratch';
  @override
  RoundFamily get family => RoundFamily.touch;
  @override
  int get unlockRound => 9;
  @override
  Round create(RoundContext ctx) => ScratchRound(ctx);
}

class ScratchRound extends Round {
  ScratchRound(super.ctx) {
    final rng = ctx.rng;
    need = 1.4 + ctx.difficulty * 0.8; // total rubbing distance, in heights
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      x: rng.rangeDouble(0.35, 0.65),
      y: rng.rangeDouble(0.45, 0.65),
      radius: 0.22,
    )..dust = 1;
  }

  late final double need;
  late final GameButton button;
  double rubbed = 0;
  double _lx = 0, _ly = 0;
  bool _down = false;

  @override
  String get instruction => 'Rub it until it shines';
  @override
  String get hint => 'Scrub back and forth';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 3.6;
  @override
  bool get allowSwap => false;

  void _add(double d) {
    rubbed += d;
    final f = (rubbed / need).clamp(0.0, 1.0);
    button
      ..dust = 1 - f
      ..ring = f;
    if (f >= 1) succeed();
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') {
      _down = true;
      _lx = _ly = 0;
    }
  }

  @override
  void onDrag(String? targetId, double dx, double dy) {
    if (!_down || targetId != 'main') return;
    final step = math.sqrt((dx - _lx) * (dx - _lx) + (dy - _ly) * (dy - _ly));
    _lx = dx;
    _ly = dy;
    _add(math.min(step, 0.2));
  }

  @override
  void onPressUp(String? targetId) {
    if (targetId == 'main') _down = false;
  }

  /// Demo only: rub a little every frame.
  void demoRub(double dt) => _add(dt * 2.4);

  @override
  void onTimeout() => fail('Still dusty.');

  @override
  String? demoMove() => 'rub:main';
}
