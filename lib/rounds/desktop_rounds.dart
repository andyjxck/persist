import 'dart:math' as math;
import 'dart:ui';

import 'round.dart';

// Rounds that only exist in the web/desktop version. They use the wide play
// area, the cursor and the keyboard. Positions are normalised (0..1) like
// every other round; distances are converted with ctx.aspect so they are
// measured in play-area heights on both axes.

// ---------------------------------------------------------------------------
// Chase: the button runs away from the cursor across the whole stage.
// ---------------------------------------------------------------------------

class ChaseType extends RoundType {
  const ChaseType();
  @override
  String get id => 'chase';
  @override
  RoundFamily get family => RoundFamily.desk;
  @override
  int get unlockRound => 4;
  @override
  double weight(int roundIndex) => 1.3;
  @override
  Round create(RoundContext ctx) => ChaseRound(ctx);
}

class ChaseRound extends Round {
  ChaseRound(super.ctx) {
    final rng = ctx.rng;
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      x: rng.chance(0.5) ? 0.2 : 0.8,
      y: rng.rangeDouble(0.3, 0.7),
      radius: 0.12 - ctx.difficulty * 0.02,
    );
    speed = 0.9 + ctx.difficulty * 0.9; // heights per second when fleeing
    nerve = 0.34 + ctx.difficulty * 0.08; // how close the cursor may get
    _slip = rng.chance(0.5) ? 1 : -1;
  }

  late final GameButton button;
  late final double speed;
  late final double nerve;
  late final int _slip;
  double? _cx;
  double? _cy;

  @override
  String get instruction => 'Catch it';
  @override
  String get hint => 'Corner it';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 4.2;
  @override
  bool get allowSwap => false;

  @override
  void onHover(double? x, double? y) {
    _cx = x;
    _cy = y;
  }

  @override
  void tick(double dt) {
    final cx = _cx, cy = _cy;
    if (cx == null || cy == null) return;
    final a = ctx.aspect;
    var dx = (button.x - cx) * a;
    var dy = button.y - cy;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d > nerve || d < 1e-6) return;
    dx /= d;
    dy /= d;
    // Near a wall it slides sideways instead of getting stuck.
    final rx = button.radius / a;
    final ry = button.radius;
    final nearX = button.x < rx + 0.03 || button.x > 1 - rx - 0.03;
    final nearY = button.y < ry + 0.03 || button.y > 1 - ry - 0.03;
    if (nearX) dy += _slip * 0.9;
    if (nearY) dx += _slip * 0.9;
    final push = speed * (1 - d / nerve) * dt * 2.2;
    button
      ..x = (button.x + dx * push / a).clamp(rx, 1 - rx)
      ..y = (button.y + dy * push).clamp(ry, 1 - ry);
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') succeed();
  }

  @override
  void onTimeout() => fail('It outran you.');

  @override
  String? demoMove() => 'main';
}

// ---------------------------------------------------------------------------
// Keyboard traps: press a key (not the mouse), or click without touching keys.
// ---------------------------------------------------------------------------

class KeyTrapType extends RoundType {
  const KeyTrapType();
  @override
  String get id => 'key_trap';
  @override
  RoundFamily get family => RoundFamily.desk;
  @override
  int get unlockRound => 5;
  @override
  Round create(RoundContext ctx) => KeyTrapRound(ctx);
}

class KeyTrapRound extends Round {
  KeyTrapRound(super.ctx) {
    final rng = ctx.rng;
    letter = rng.pick(const ['A', 'S', 'D', 'F', 'J', 'K', 'L', 'G', 'H']);
    handsOff = ctx.difficulty > 0.12 && rng.chance(0.45);
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      label: handsOff ? 'SPACE' : letter,
      x: rng.rangeDouble(0.3, 0.7),
      y: rng.rangeDouble(0.4, 0.6),
      radius: 0.2,
      shape: ButtonShape.key,
    );
    _text = handsOff ? 'Click it. Hands off the keyboard.' : 'Press $letter on your keyboard';
  }

  late final String letter;
  late final bool handsOff;
  late final GameButton button;
  late final String _text;

  @override
  String get instruction => _text;
  @override
  String get hint => handsOff ? 'Mouse only' : 'Keyboard only. No clicking.';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 2.6;

  @override
  void onKey(String key) {
    if (handsOff) {
      fail('You touched the keyboard ($key).');
    } else if (key.toUpperCase() == letter) {
      button.pressed = true;
      succeed();
    } else {
      fail('That was ${key.toUpperCase()}, not $letter.');
    }
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId != 'main') return;
    if (handsOff) {
      succeed();
    } else {
      fail('It said keyboard. You clicked.');
    }
  }

  @override
  String? demoMove() => handsOff ? 'main' : 'key:$letter';
}

// ---------------------------------------------------------------------------
// Hover: rest the cursor on it, but don't click.
// ---------------------------------------------------------------------------

class HoverHoldType extends RoundType {
  const HoverHoldType();
  @override
  String get id => 'hover_hold';
  @override
  RoundFamily get family => RoundFamily.desk;
  @override
  int get unlockRound => 7;
  @override
  Round create(RoundContext ctx) => HoverHoldRound(ctx);
}

class HoverHoldRound extends Round {
  HoverHoldRound(super.ctx) {
    final rng = ctx.rng;
    need = rng.rangeDouble(0.8, 1.1 + ctx.difficulty * 0.4);
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      label: rng.pick(const ['CLICK', 'CLICK ME', 'GO']),
      x: rng.rangeDouble(0.25, 0.75),
      y: rng.rangeDouble(0.35, 0.65),
      radius: 0.17,
    );
    drifts = ctx.difficulty > 0.3 && rng.chance(0.5);
    _phase = rng.rangeDouble(0, math.pi * 2);
  }

  late final double need;
  late final GameButton button;
  late final bool drifts;
  late final double _phase;
  late final double _homeX = button.x;
  late final double _homeY = button.y;
  double hovered = 0;
  bool _over = false;

  @override
  String get instruction => 'Hover over it. Do NOT click.';
  @override
  String get hint => _over ? 'Stay there...' : 'Rest your cursor on it';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get timeLimit => need + 2.0 * ctx.timerFactor;
  @override
  double get baseTime => need + 2.0;

  @override
  void onHover(double? x, double? y) {
    if (x == null || y == null) {
      _over = false;
      return;
    }
    final dx = (x - button.x) * ctx.aspect;
    final dy = y - button.y;
    _over = math.sqrt(dx * dx + dy * dy) <= button.radius;
  }

  @override
  void tick(double dt) {
    if (drifts) {
      button
        ..x = _homeX + math.sin(elapsed * 1.7 + _phase) * 0.06
        ..y = _homeY + math.cos(elapsed * 1.3 + _phase) * 0.06;
    }
    if (_over) {
      hovered += dt;
    } else {
      hovered = math.max(0, hovered - dt * 1.5);
    }
    button.ring = (hovered / need).clamp(0, 1);
    if (hovered >= need) succeed();
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') fail('It said hover. You clicked.');
  }

  @override
  void onTimeout() => fail(hovered > 0 ? 'Not long enough.' : 'You never hovered.');

  @override
  String? demoMove() => 'hover:main';
}

// ---------------------------------------------------------------------------
// Magnet: the button follows your cursor. Don't let it touch.
// ---------------------------------------------------------------------------

class MagnetType extends RoundType {
  const MagnetType();
  @override
  String get id => 'magnet';
  @override
  RoundFamily get family => RoundFamily.desk;
  @override
  int get unlockRound => 10;
  @override
  Round create(RoundContext ctx) => MagnetRound(ctx);
}

class MagnetRound extends Round {
  MagnetRound(super.ctx) {
    final rng = ctx.rng;
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      x: rng.rangeDouble(0.3, 0.7),
      y: rng.rangeDouble(0.3, 0.7),
      radius: 0.11,
    );
    speed = 0.35 + ctx.difficulty * 0.35;
  }

  late final GameButton button;
  late final double speed;
  double? _cx;
  double? _cy;
  bool _placed = false;

  @override
  String get instruction => "Don't let it touch your cursor";
  @override
  String get hint => 'Survive the timer';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 3.4;
  @override
  bool get allowSwap => false;

  @override
  void onHover(double? x, double? y) {
    _cx = x;
    _cy = y;
  }

  @override
  void tick(double dt) {
    final cx = _cx, cy = _cy;
    if (cx == null || cy == null) return;
    final a = ctx.aspect;
    if (!_placed) {
      // The cursor is usually still where the last round's button was, which
      // is right where this one appears. Start it on the far side instead of
      // catching the cursor before the player can read the instruction.
      _placed = true;
      final gx = (cx - button.x) * a;
      final gy = cy - button.y;
      if (math.sqrt(gx * gx + gy * gy) < button.radius + 0.3) {
        final rx = button.radius / math.max(0.2, a);
        button
          ..x = (cx < 0.5 ? 0.88 : 0.12).clamp(rx, 1 - rx)
          ..y = (cy < 0.5 ? 0.85 : 0.15).clamp(button.radius, 1 - button.radius);
      }
    }
    final dx = (cx - button.x) * a;
    final dy = cy - button.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d <= button.radius * 0.95) {
      fail('It caught your cursor.');
      return;
    }
    final step = math.min(d, speed * dt * (1 + elapsed * 0.25));
    button
      ..x += dx / d * step / a
      ..y += dy / d * step;
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') fail('You clicked it. It wanted that.');
  }

  @override
  void onTimeout() => succeed();

  @override
  String? demoMove() => null;
}

// ---------------------------------------------------------------------------
// Grid: a wall of buttons. Press every one of a colour, or find the odd one.
// ---------------------------------------------------------------------------

class GridType extends RoundType {
  const GridType();
  @override
  String get id => 'grid';
  @override
  RoundFamily get family => RoundFamily.desk;
  @override
  int get unlockRound => 6;
  @override
  Round create(RoundContext ctx) => GridRound(ctx);
}

class GridRound extends Round {
  GridRound(super.ctx) {
    final rng = ctx.rng;
    oddOneOut = ctx.difficulty > 0.2 && rng.chance(0.4);
    const cols = 7, rows = 3;
    final a = ctx.aspect;
    final cellW = 1 / cols, cellH = 1 / rows;
    final r = 0.36 * math.min(cellW * a, cellH);
    final colours = rng.shuffled(GameColour.all).take(3).toList();
    final odd = rng.nextInt(cols * rows);
    _buttons = [];
    for (var i = 0; i < cols * rows; i++) {
      final c = i % cols, row = i ~/ cols;
      GameColour colour;
      if (oddOneOut) {
        final base = colours.first;
        colour = i == odd ? GameColour(base.name, _shift(base.color, 0.16)) : base;
      } else {
        colour = rng.pick(colours);
      }
      _buttons.add(
        GameButton(id: 'g$i', colour: colour, x: (c + 0.5) * cellW, y: (row + 0.5) * cellH, radius: r),
      );
    }
    if (oddOneOut) {
      _targets = {'g$odd'};
      _text = 'Press the odd one out';
    } else {
      // Make sure there are 3 to 6 of the asked colour.
      asked = colours.first;
      final want = rng.range(3, 4 + (ctx.difficulty * 2).round());
      final order = rng.shuffled(List.generate(_buttons.length, (i) => i));
      var have = _buttons.where((b) => b.colour == asked).length;
      for (final i in order) {
        final b = _buttons[i];
        if (have > want && b.colour == asked) {
          b.colour = colours[1];
          have--;
        } else if (have < want && b.colour != asked) {
          b.colour = asked;
          have++;
        }
      }
      _targets = {for (final b in _buttons) if (b.colour == asked) b.id};
      _text = 'Press every ${asked.name} one';
    }
  }

  static Color _shift(Color c, double amount) => Color.lerp(c, const Color(0xFFFFFFFF), amount)!;

  late final bool oddOneOut;
  late final List<GameButton> _buttons;
  late final Set<String> _targets;
  late final String _text;
  GameColour asked = GameColour.red;
  final Set<String> _done = {};

  @override
  String get instruction => _text;
  @override
  String get hint => oddOneOut ? 'One of these is slightly different' : '${_targets.length - _done.length} left';
  @override
  List<GameButton> get buttons => _buttons;
  @override
  double get baseTime => oddOneOut ? 4.5 : 2.2 + 0.55 * _targets.length;
  @override
  bool get allowSwap => false;
  @override
  GameColour get rememberedColour => oddOneOut ? _buttons.first.colour : asked;
  @override
  bool ringAround(GameButton b) => false;
  @override
  bool get frameTimer => true; // one clock around the whole grid

  @override
  void onPressDown(String? targetId) {
    if (targetId == null || _done.contains(targetId)) return;
    if (_targets.contains(targetId)) {
      _done.add(targetId);
      _buttons.firstWhere((b) => b.id == targetId).spent = true;
      if (_done.length == _targets.length) succeed();
    } else if (targetId.startsWith('g')) {
      fail(oddOneOut ? 'Not that one. Look closer.' : 'That one was not ${asked.name}.');
    }
  }

  @override
  void onTimeout() => fail(oddOneOut ? 'You never found it.' : '${_targets.length - _done.length} still to press.');

  @override
  String? demoMove() => _targets.firstWhere((t) => !_done.contains(t), orElse: () => '');
}
