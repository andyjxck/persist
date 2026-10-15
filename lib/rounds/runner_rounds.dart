import 'dart:math' as math;

import 'layout.dart';
import 'round.dart';

// ---------------------------------------------------------------------------
// The button dodges.
// ---------------------------------------------------------------------------

class DodgerType extends RoundType {
  const DodgerType();
  @override
  String get id => 'dodger';
  @override
  RoundFamily get family => RoundFamily.runner;
  @override
  int get unlockRound => 4;
  @override
  double weight(int roundIndex) => 1.3;
  @override
  Round create(RoundContext ctx) => DodgerRound(ctx);
}

class DodgerRound extends Round {
  @override
  String? demoMove() => 'main';

  DodgerRound(super.ctx) {
    final rng = ctx.rng;
    final spot = randomSpot(rng);
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      x: spot.$1,
      y: spot.$2,
      radius: 0.17 - ctx.difficulty * 0.04,
    );
    teleports = rng.chance(0.4);
    // Pre-roll every destination so the Daily run is the same for everyone.
    _targets = [for (var i = 0; i < 40; i++) randomSpot(rng)];
    speed = 0.6 + ctx.difficulty * 0.7; // play-area widths per second
    hopEvery = (0.9 - ctx.difficulty * 0.4).clamp(0.45, 0.9);
  }

  late final GameButton button;
  late final bool teleports;
  late final List<(double, double)> _targets;
  late final double speed;
  late final double hopEvery;
  int _targetIndex = 0;
  double _sinceHop = 0;

  @override
  String get instruction => teleports ? 'Catch it' : 'Press it (if you can)';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 3.0;

  @override
  void tick(double dt) {
    if (teleports) {
      _sinceHop += dt;
      if (_sinceHop >= hopEvery) {
        _sinceHop = 0;
        final t = _targets[_targetIndex++ % _targets.length];
        button
          ..x = t.$1
          ..y = t.$2;
      }
    } else {
      final t = _targets[_targetIndex % _targets.length];
      final dx = t.$1 - button.x;
      final dy = t.$2 - button.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final step = speed * dt;
      if (dist <= step) {
        _targetIndex++;
      } else {
        button
          ..x += dx / dist * step
          ..y += dy / dist * step;
      }
    }
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') succeed();
  }

  @override
  void onTimeout() => fail('It got away.');
}

// ---------------------------------------------------------------------------
// The button shrinks away to nothing.
// ---------------------------------------------------------------------------

class ShrinkerType extends RoundType {
  const ShrinkerType();
  @override
  String get id => 'shrinker';
  @override
  RoundFamily get family => RoundFamily.runner;
  @override
  int get unlockRound => 3;
  @override
  Round create(RoundContext ctx) => ShrinkerRound(ctx);
}

class ShrinkerRound extends Round {
  @override
  String? demoMove() => elapsed < 0.6 ? null : 'main';

  ShrinkerRound(super.ctx) {
    final rng = ctx.rng;
    final spot = randomSpot(rng);
    button = GameButton(id: 'main', colour: rng.pick(GameColour.all), x: spot.$1, y: spot.$2);
    startRadius = 0.26;
  }

  late final GameButton button;
  late final double startRadius;

  @override
  String get instruction => "Press it before it's gone";
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 2.6;
  @override
  bool get showTimer => false; // the button IS the timer

  @override
  void tick(double dt) {
    final left = 1 - (elapsed / timeLimit).clamp(0.0, 1.0);
    button.radius = math.max(0.012, startRadius * left);
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') succeed();
  }

  @override
  void onTimeout() => fail('It vanished.');
}

// ---------------------------------------------------------------------------
// The button splits into decoys and shuffles (keep your eye on the real one).
// ---------------------------------------------------------------------------

class DecoyType extends RoundType {
  const DecoyType();
  @override
  String get id => 'decoys';
  @override
  RoundFamily get family => RoundFamily.runner;
  @override
  int get unlockRound => 11;
  @override
  Round create(RoundContext ctx) => DecoyRound(ctx);
}

class DecoyRound extends Round {
  @override
  String? demoMove() => shuffling ? null : 'real';

  DecoyRound(super.ctx) {
    final rng = ctx.rng;
    final count = ctx.difficulty > 0.6 ? 4 : 3;
    colour = rng.pick(GameColour.all);
    _slots = slotsFor(count);
    _buttons = [
      for (var i = 0; i < count; i++)
        GameButton(id: i == 0 ? 'real' : 'decoy$i', colour: colour, radius: radiusFor(count)),
    ];
    // slotOf[i] = which slot button i sits in.
    slotOf = [for (var i = 0; i < count; i++) i];
    swapCount = 3 + (ctx.difficulty * 5).round();
    swapTime = (0.42 - ctx.difficulty * 0.14).clamp(0.24, 0.42);
    _swaps = [for (var i = 0; i < swapCount; i++) _pickPair(rng.nextInt(count), rng.range(1, count - 1), count)];
    _real.label = 'ME';
  }

  static (int, int) _pickPair(int a, int offset, int count) => (a, (a + offset) % count);

  late final GameColour colour;
  late final List<(double, double)> _slots;
  late final List<GameButton> _buttons;
  late final List<int> slotOf;
  late final int swapCount;
  late final double swapTime;
  late final List<(int, int)> _swaps;
  static const splitAt = 0.7;

  GameButton get _real => _buttons.first;
  double get shuffleEnd => splitAt + swapCount * swapTime;
  bool get shuffling => elapsed < shuffleEnd;

  @override
  String get instruction =>
      elapsed < splitAt ? 'Watch this one' : (shuffling ? 'Keep watching...' : 'Press the real one');
  @override
  List<GameButton> get buttons => _buttons;
  @override
  double get baseTime => 2.2;
  @override
  double get timeLimit => shuffleEnd + baseTime * ctx.timerFactor;
  @override
  bool get allowSwap => false;

  @override
  void tick(double dt) {
    final split = elapsed >= splitAt;
    for (final b in _buttons.skip(1)) {
      b.visible = split;
    }
    if (!split) {
      // Decoys hide behind the real one, then burst out of it.
      final s = _slots[slotOf[0]];
      for (final b in _buttons) {
        b
          ..x = s.$1
          ..y = s.$2;
      }
      return;
    }
    _real.label = '';
    final t = elapsed - splitAt;
    final swapIndex = (t / swapTime).floor();
    // Apply all finished swaps.
    final slots = [for (var i = 0; i < _buttons.length; i++) i];
    for (var s = 0; s < math.min(swapIndex, swapCount); s++) {
      final (a, b) = _swaps[s];
      final ia = slots.indexOf(a);
      final ib = slots.indexOf(b);
      slots[ia] = b;
      slots[ib] = a;
    }
    for (var i = 0; i < _buttons.length; i++) {
      final p = _slots[slots[i]];
      _buttons[i]
        ..x = p.$1
        ..y = p.$2;
    }
    // Animate the swap in progress along a little arc.
    if (swapIndex < swapCount) {
      final (a, b) = _swaps[swapIndex];
      final f = (t - swapIndex * swapTime) / swapTime;
      final e = f * f * (3 - 2 * f);
      final ia = slots.indexOf(a);
      final ib = slots.indexOf(b);
      final pa = _slots[a];
      final pb = _slots[b];
      final lift = math.sin(e * math.pi) * 0.12;
      _buttons[ia]
        ..x = pa.$1 + (pb.$1 - pa.$1) * e
        ..y = pa.$2 + (pb.$2 - pa.$2) * e - lift;
      _buttons[ib]
        ..x = pb.$1 + (pa.$1 - pb.$1) * e
        ..y = pb.$2 + (pa.$2 - pb.$2) * e + lift;
    }
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == null || elapsed < splitAt) return;
    if (targetId == 'real') {
      succeed();
    } else if (targetId.startsWith('decoy')) {
      fail('That was a decoy.');
    }
  }

  @override
  void onTimeout() => fail('Too slow. The real one got bored.');
}
