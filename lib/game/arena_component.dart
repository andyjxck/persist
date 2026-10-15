import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../logic/run_engine.dart';
import '../rounds/round.dart';
import '../ui/theme.dart';
import 'button_panic_game.dart';
import 'fx.dart';

/// Per-button animation state (kept across frames, keyed by button id).
class _ButtonFx {
  final Spring press = Spring();
  double hover = 0;
  double dustSeen = 1;
}

/// Draws everything during play: HUD, instruction, buttons with their timer
/// rings, fake overlays, banners and effects, with the chaos layers (shake,
/// rotation, inversion) on top. It also turns a screen point into "what was
/// tapped", undoing the same transforms so input lands where things look.
class ArenaComponent extends Component with HasGameReference<ButtonPanicGame> {
  final FxLayer fx = FxLayer();
  final Map<String, _ButtonFx> _bfx = {};
  Round? _seenRound;
  double roundAge = 0;
  double _time = 0;

  // Success stamp and fail flash.
  String _stamp = '';
  double _stampAge = 99;
  double _failAge = 99;
  double _wonAge = 99;

  bool get wide => game.wide;
  Size get _screen => Size(game.size.x, game.size.y);

  // ---------------------------------------------------------------------------
  // Layout (two tuned layouts: wide web stage, tall phone screen)
  // ---------------------------------------------------------------------------

  double get _pad => wide ? 28 : 16;
  double get hudHeight => wide ? 64 : 56;

  Rect get columnRect {
    final s = _screen;
    final w = wide ? s.width : math.min(s.width, 560.0);
    return Rect.fromLTWH((s.width - w) / 2, 0, w, s.height);
  }

  double get _instructionHeight => wide ? 104 : math.max(128, _screen.height * 0.2);

  Rect get instructionRect {
    final c = columnRect;
    return Rect.fromLTWH(c.left + _pad, hudHeight, c.width - 2 * _pad, _instructionHeight);
  }

  /// Where buttons live. Positions in rounds are 0..1 inside this rect.
  Rect get playRect {
    final c = columnRect;
    final top = instructionRect.bottom + (wide ? 8 : 12);
    final bottom = _screen.height - (wide ? 28 : 28);
    return Rect.fromLTRB(c.left + _pad, top, c.right - _pad, math.max(top + 120, bottom));
  }

  double get aspect => playRect.width / math.max(1, playRect.height);

  double get _unit => math.min(playRect.width, playRect.height);

  Offset _toScreen(GameButton b) {
    final p = playRect;
    return Offset(p.left + b.x * p.width + b.dragX * p.height, p.top + b.y * p.height + b.dragY * p.height);
  }

  Offset toPlay(Offset screen) {
    final p = playRect;
    final q = untransform(screen);
    return Offset((q.dx - p.left) / p.width, (q.dy - p.top) / p.height);
  }

  Rect _overlayRect(Rect r) {
    final p = playRect;
    return Rect.fromLTRB(
      p.left + r.left * p.width,
      p.top + r.top * p.height,
      p.left + r.right * p.width,
      p.top + r.bottom * p.height,
    );
  }

  double _radius(GameButton b) => b.radius * _unit;

  // ---------------------------------------------------------------------------
  // Hit testing
  // ---------------------------------------------------------------------------

  /// Undo shake and rotation so we test against where things are drawn.
  Offset untransform(Offset p) {
    final c = _screen.center(Offset.zero);
    final q = p - game.shakeOffset - c;
    final a = -game.rotation;
    return Offset(q.dx * math.cos(a) - q.dy * math.sin(a), q.dx * math.sin(a) + q.dy * math.cos(a)) + c;
  }

  /// The id of the overlay or button under [screenPoint], or null.
  String? hitTest(Offset screenPoint, Round round, {bool overlays = true}) {
    final p = untransform(screenPoint);
    if (overlays) {
      for (final o in round.overlays.reversed) {
        if (!o.blocksInput) continue;
        if (_overlayRect(o.rect).contains(p)) return o.id;
      }
    }
    // Fingers are fatter than cursors.
    final slack = wide ? 2.0 : 8.0;
    for (final b in round.buttons.reversed) {
      if (!b.visible || b.spent) continue;
      final centre = _toScreen(b);
      final r = _radius(b);
      if (b.shape == ButtonShape.key) {
        if (_keyRect(centre, r).inflate(slack).contains(p)) return b.id;
      } else if ((p - centre).distance <= r * 1.06 + slack) {
        return b.id;
      }
    }
    return null;
  }

  Rect _keyRect(Offset c, double r) => Rect.fromCenter(center: c, width: r * 2.1, height: r * 1.9);

  // ---------------------------------------------------------------------------
  // Events from the game
  // ---------------------------------------------------------------------------

  static const _words = ['NICE', 'CLEAN', 'YES', 'SURVIVED', 'SHARP', 'PHEW', 'OK FINE', 'NAILED'];

  void onSuccess(Round r, String? pressedId) {
    _wonAge = 0;
    _stampAge = 0;
    _stamp = _words[(game.engine?.roundIndex ?? 0) % _words.length];
    final targets = r.buttons.where((b) => b.visible && (pressedId == null || b.id == pressedId)).toList();
    for (final b in targets.take(3)) {
      final c = _toScreen(b);
      final rad = _radius(b);
      fx.burst(c, rad, [b.colour.color, BP.paper, BP.mint], count: targets.length > 1 ? 14 : 30);
      fx.wave(c, rad, rad * 2.3, BP.paper, width: 5);
    }
  }

  void onFail(Round r, String? pressedId) {
    _failAge = 0;
    final targets = r.buttons.where((b) => b.visible && (pressedId == null || b.id == pressedId));
    for (final b in targets.take(2)) {
      final c = _toScreen(b);
      fx.shatter(c, _radius(b), b.colour.color);
      fx.wave(c, _radius(b), _radius(b) * 1.8, BP.signal, width: 8, life: 0.35);
    }
  }

  @override
  void update(double dt) {
    _time += dt;
    roundAge += dt;
    _stampAge += dt;
    _failAge += dt;
    _wonAge += dt;
    final r = game.round;
    if (!identical(r, _seenRound)) {
      _seenRound = r;
      roundAge = 0;
      _wonAge = 99;
      _bfx.clear();
    }
    fx.update(dt);
    if (r == null) return;
    final hoverId = game.hoverScreen == null ? null : hitTest(game.hoverScreen!, r, overlays: false);
    for (final b in r.buttons) {
      final s = _bfx.putIfAbsent(b.id, _ButtonFx.new);
      s.press.target = (b.pressed || b.spent) ? 1 : 0;
      s.press.update(dt);
      final wantHover = (hoverId == b.id && game.phase == GamePhase.playing) ? 1.0 : 0.0;
      s.hover += (wantHover - s.hover) * math.min(1, dt * 14);
      if (b.dust < s.dustSeen - 0.02) {
        fx.dust(_toScreen(b), _radius(b));
        s.dustSeen = b.dust;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Drawing
  // ---------------------------------------------------------------------------

  static const _invertMatrix = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  @override
  void render(Canvas canvas) {
    final screen = Offset.zero & _screen;
    final round = game.round;
    final calm = game.chaos.calm && round != null;
    _drawBackground(canvas, screen, calm);
    if (round == null) return;
    final chaos = game.chaos;
    // Never invert a round whose answer is a colour: it makes the screen lie.
    final colourSafe = game.round?.allowInvert ?? true;
    final invert = colourSafe && ((chaos.invert && game.phase == GamePhase.playing) || game.flashInvert > 0);

    if (invert) {
      canvas.saveLayer(screen, Paint()..colorFilter = const ColorFilter.matrix(_invertMatrix));
    } else {
      canvas.save();
    }

    canvas.save();
    final c = _screen.center(Offset.zero);
    canvas.translate(game.shakeOffset.dx + c.dx, game.shakeOffset.dy + c.dy);
    canvas.rotate(game.rotation);
    canvas.translate(-c.dx, -c.dy);

    _drawHud(canvas, round);
    _drawInstruction(canvas, round);

    final exit = game.phase == GamePhase.roundWon ? easeOutCubic((_wonAge / 0.3).clamp(0.0, 1.0)) : 0.0;
    final timeF = round.timeLimit <= 0 ? 0.0 : (round.timeLeft / round.timeLimit).clamp(0.0, 1.0);
    if (round.frameTimer && round.showTimer) _drawFrameTimer(canvas, round, timeF, exit);
    var i = 0;
    for (final b in round.buttons) {
      if (b.visible) _drawButton(canvas, round, b, i, timeF, exit, calm);
      i++;
    }
    for (final o in round.overlays) {
      _drawOverlay(canvas, o, round);
    }
    fx.render(canvas);
    if (_stampAge < 0.7) _drawStamp(canvas);
    canvas.restore();

    if (_failAge < 0.6) _drawFailFlash(canvas, screen);
    if (game.bannerTime > 0 && game.banner.isNotEmpty) _drawBanner(canvas);
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Rect screen, bool calm) {
    final base = calm ? BP.calmBg : BP.ink;
    canvas.drawRect(screen, Paint()..color = base);
    // Soft light from above the play area.
    final p = playRect;
    canvas.drawRect(
      screen,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(p.center.dx, p.top + p.height * 0.35),
          math.max(p.width, p.height) * 0.75,
          [(calm ? BP.calm : BP.paper).withValues(alpha: 0.07), const Color(0x00000000)],
        ),
    );
    // A faint dot grid, so the stage has a surface.
    final dot = Paint()..color = (calm ? BP.calm : BP.paper).withValues(alpha: 0.045);
    const step = 28.0;
    final ox = (screen.width % step) / 2;
    for (var y = hudHeight + step / 2; y < screen.height; y += step) {
      for (var x = ox; x < screen.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  // --- Text ------------------------------------------------------------------

  final Map<String, TextPainter> _tpCache = {};

  TextPainter _tp(InlineSpan span, double maxWidth, {int maxLines = 3, TextAlign align = TextAlign.center}) {
    final key = '${span.hashCode}|$maxWidth|$maxLines|$align';
    final hit = _tpCache[key];
    if (hit != null) return hit;
    if (_tpCache.length > 160) _tpCache.clear();
    final tp = TextPainter(text: span, textAlign: align, textDirection: TextDirection.ltr, maxLines: maxLines, ellipsis: '…')
      ..layout(maxWidth: maxWidth);
    return _tpCache[key] = tp;
  }

  void _text(Canvas canvas, String text, Offset centre, TextStyle style, {double maxWidth = 400, int maxLines = 2}) {
    final tp = _tp(TextSpan(text: text, style: style), maxWidth, maxLines: maxLines);
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  // --- HUD -------------------------------------------------------------------

  void _drawHud(Canvas canvas, Round round) {
    final col = columnRect;
    final left = col.left + _pad;
    final mid = hudHeight / 2 + (wide ? 4 : 2);
    final lbl = _tp(TextSpan(text: 'ROUND', style: BP.label(10, color: BP.faint)), 100);
    lbl.paint(canvas, Offset(left, mid - lbl.height - 1));
    final num = _tp(TextSpan(text: '${round.ctx.roundIndex + 1}', style: BP.d(wide ? 22 : 20, weight: FontWeight.w800)), 120);
    num.paint(canvas, Offset(left, mid - 2));

    // Mode chip (right side; on phones leave room for the mute button).
    final e = game.engine;
    final mode = e?.mode == GameMode.daily ? 'DAILY' : (game.isPractice ? 'PRACTICE' : 'ENDLESS');
    final chip = _tp(TextSpan(text: mode, style: BP.label(10, color: BP.muted)), 120);
    final right = col.right - _pad - (wide ? 0 : 52);
    final chipRect = Rect.fromLTWH(right - chip.width - 20, mid - 12, chip.width + 20, 24);
    canvas.drawRRect(RRect.fromRectAndRadius(chipRect, const Radius.circular(12)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = BP.line);
    chip.paint(canvas, chipRect.center - Offset(chip.width / 2, chip.height / 2));

    // Active chaos layers, quietly.
    final layers = game.chaos.activeLayers.where((l) => l != 'calm').toList();
    if (layers.isNotEmpty) {
      final t = _tp(TextSpan(text: layers.map((l) => l.toUpperCase()).join('  ·  '), style: BP.label(9.5, color: BP.signal.withValues(alpha: 0.75))), 260);
      t.paint(canvas, Offset(col.center.dx - t.width / 2, mid - t.height / 2));
    }
  }

  // --- Instruction -------------------------------------------------------------

  static const _negations = {"DON'T", 'NOT', 'NEVER', 'NO', 'BOTH', 'EVERY'};

  List<TextSpan> _emphasise(String text, TextStyle base) {
    final spans = <TextSpan>[];
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final bare = w.replaceAll(RegExp("[^A-Za-z']"), '');
      Color? c;
      if (_negations.contains(bare) && bare == bare.toUpperCase()) c = BP.signal;
      for (final gc in GameColour.all) {
        if (bare == gc.name) c = gc.color;
      }
      spans.add(TextSpan(text: i == words.length - 1 ? w : '$w ', style: c == null ? base : base.copyWith(color: c)));
    }
    return spans;
  }

  void _drawInstruction(Canvas canvas, Round round) {
    final r = instructionRect;
    final calm = round.isCalm;
    final hint = round.hint;
    final intro = easeOutCubic((roundAge / 0.24).clamp(0.0, 1.0));
    final exit = game.phase == GamePhase.roundWon ? easeOutCubic((_wonAge / 0.25).clamp(0.0, 1.0)) : 0.0;
    final alpha = intro * (1 - exit * 0.7);
    final dy = (1 - intro) * 14 - exit * 8;

    // Fit the instruction: largest size that fits in two lines.
    final maxSize = wide ? 40.0 : 30.0;
    TextPainter? tp;
    for (var size = maxSize; size >= 16; size -= 2) {
      final style = calm
          ? BP.d(size, color: BP.calm.withValues(alpha: alpha), weight: FontWeight.w600)
          : BP.d(size, color: BP.paper.withValues(alpha: alpha));
      final span = TextSpan(children: _emphasise(round.instruction, style));
      tp = TextPainter(text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr, maxLines: 2)
        ..layout(maxWidth: r.width);
      if (!tp.didExceedMaxLines && tp.height <= r.height - (hint.isEmpty ? 8 : 34)) break;
    }
    final hintTp = hint.isEmpty
        ? null
        : _tp(TextSpan(text: hint, style: BP.t(wide ? 15 : 14, color: BP.muted.withValues(alpha: alpha), weight: FontWeight.w600)), r.width, maxLines: 1);
    final total = tp!.height + (hintTp == null ? 0 : hintTp.height + 8);
    final top = r.center.dy - total / 2 + dy;
    tp.paint(canvas, Offset(r.center.dx - tp.width / 2, top));
    hintTp?.paint(canvas, Offset(r.center.dx - hintTp.width / 2, top + tp.height + 8));
  }

  // --- Buttons ---------------------------------------------------------------

  void _drawButton(Canvas canvas, Round round, GameButton b, int index, double timeF, double exit, bool calm) {
    final centre = _toScreen(b);
    var r = _radius(b);
    if (r < 1) return;
    final s = _bfx.putIfAbsent(b.id, _ButtonFx.new);

    // Entrance pop (staggered), exit swell-and-fade.
    final popT = ((roundAge - index * 0.035) / 0.38).clamp(0.0, 1.0);
    final pop = elasticOut(popT);
    final scale = pop * (1 + exit * 0.12);
    final alpha = (1 - exit).clamp(0.0, 1.0) * (b.spent ? 0.38 : 1.0);
    if (scale <= 0.01 || alpha <= 0.01) return;
    r *= scale;

    // Timer ring first, so it sits behind the button's glow.
    if (round.ringAround(b) && round.verdict == Verdict.pending && game.phase == GamePhase.playing) {
      _drawTimerRing(canvas, b, centre, r, timeF, calm, pop);
    }

    final press = s.press.x.clamp(-0.3, 1.2);
    final hover = s.hover;
    final base = b.colour.color;
    final depth = math.max(5.0, r * 0.16) * (1 + hover * 0.15);
    final sink = depth * press * 0.78;
    final face = b.highlighted ? BP.tint(base, 0.4) : (b.spent ? Color.lerp(base, const Color(0xFF6A6575), 0.6)! : base);

    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(255, 255, 255, alpha));

    if (b.highlighted || hover > 0.01) {
      canvas.drawCircle(
        centre,
        r * (1.25 + (b.highlighted ? 0.15 : 0)),
        Paint()
          ..color = base.withValues(alpha: b.highlighted ? 0.55 : 0.22 * hover)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
      );
    }

    if (b.shape == ButtonShape.key) {
      _drawKeycap(canvas, b, centre, r, depth, sink, face, press);
    } else {
      _drawRoundButton(canvas, b, centre, r, depth, sink, face, press, hover);
    }
    canvas.restore();
  }

  void _drawRoundButton(Canvas canvas, GameButton b, Offset centre, double r, double depth, double sink, Color face, double press, double hover) {
    // Contact shadow on the stage.
    canvas.drawOval(
      Rect.fromCenter(center: centre + Offset(0, depth + r * 0.18), width: r * 2.15, height: r * 0.9),
      Paint()
        ..color = const Color(0x8C000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.16 * (1 - press * 0.4) + 2),
    );
    // Housing (a dark bezel the button sits in).
    canvas.drawCircle(centre + Offset(0, depth * 0.55), r * 1.09, Paint()..color = const Color(0xFF07060A));
    canvas.drawCircle(
      centre + Offset(0, depth * 0.55),
      r * 1.09,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(centre - Offset(0, r), centre + Offset(0, r), [const Color(0x30FFFFFF), const Color(0x00FFFFFF)]),
    );

    // Side wall (the cylinder you see under the cap).
    final capCentre = centre + Offset(0, sink);
    final side = Path()
      ..addOval(Rect.fromCircle(center: centre + Offset(0, depth), radius: r))
      ..addRect(Rect.fromLTRB(centre.dx - r, capCentre.dy, centre.dx + r, centre.dy + depth));
    canvas.drawPath(
      side,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(centre.dx - r, 0),
          Offset(centre.dx + r, 0),
          [BP.shade(face, 0.55), BP.shade(face, 0.32), BP.shade(face, 0.6)],
          [0, 0.45, 1],
        ),
    );

    // Cap, squashed a touch when pressed (and stretched on the rebound).
    final squash = press * 0.05;
    canvas.save();
    canvas.translate(capCentre.dx, capCentre.dy);
    canvas.scale(1 + squash, 1 - squash);
    final capRect = Rect.fromCircle(center: Offset.zero, radius: r);
    final lit = BP.tint(face, 0.28 - press * 0.12);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(-r * 0.32, -r * 0.42),
          r * 1.55,
          [lit, face, BP.shade(face, 0.22 + press * 0.08)],
          [0, 0.45, 1],
        ),
    );
    // Progress fill (hold / hover / rub), rising from the bottom.
    if (b.ring > 0) {
      canvas.save();
      canvas.clipPath(Path()..addOval(capRect));
      final level = r - 2 * r * b.ring;
      final wave = Path()..moveTo(-r, r);
      for (var x = -r; x <= r; x += r / 8) {
        wave.lineTo(x, level + math.sin(x / r * 6 + _time * 9) * r * 0.035);
      }
      wave
        ..lineTo(r, r)
        ..close();
      canvas.drawPath(wave, Paint()..color = const Color(0x55FFFFFF));
      canvas.restore();
    }
    // Dust (rub rounds).
    if (b.dust > 0.01) _drawDust(canvas, b, r);
    // Rim light and specular highlight.
    canvas.drawCircle(
      Offset.zero,
      r * 0.965,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * 0.035)
        ..shader = ui.Gradient.linear(Offset(0, -r), Offset(0, r), [const Color(0x66FFFFFF), const Color(0x00FFFFFF)], [0, 0.6]),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-r * 0.22, -r * 0.5), width: r * 0.95, height: r * 0.42),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, -r * 0.72), Offset(0, -r * 0.28), [const Color(0x55FFFFFF), const Color(0x00FFFFFF)]),
    );
    _drawLabel(canvas, b, r);
    canvas.restore();
  }

  void _drawKeycap(Canvas canvas, GameButton b, Offset centre, double r, double depth, double sink, Color face, double press) {
    final outer = _keyRect(centre, r);
    final rad = Radius.circular(r * 0.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer.shift(Offset(0, depth + r * 0.12)), rad),
      Paint()
        ..color = const Color(0x8C000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.16 + 2),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(outer.shift(Offset(0, depth)), rad), Paint()..color = BP.shade(face, 0.55));
    final cap = outer.shift(Offset(0, sink));
    canvas.drawRRect(RRect.fromRectAndRadius(cap, rad), Paint()..color = BP.shade(face, 0.18));
    // Dished top face.
    final top = Rect.fromLTRB(cap.left + r * 0.16, cap.top + r * 0.1, cap.right - r * 0.16, cap.bottom - r * 0.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(top, Radius.circular(r * 0.22)),
      Paint()..shader = ui.Gradient.linear(top.topCenter, top.bottomCenter, [BP.tint(face, 0.22), face]),
    );
    canvas.save();
    canvas.translate(top.center.dx, top.center.dy);
    _drawLabel(canvas, b, r * 0.95);
    canvas.restore();
  }

  void _drawDust(Canvas canvas, GameButton b, double r) {
    final rnd = math.Random(b.id.hashCode);
    final p = Paint();
    canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xFF8A8172).withValues(alpha: 0.75 * b.dust));
    for (var i = 0; i < 70; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = math.sqrt(rnd.nextDouble()) * r * 0.95;
      final show = rnd.nextDouble();
      if (show > b.dust) continue;
      p.color = (i.isEven ? const Color(0xFFB9AE99) : const Color(0xFF5E574C)).withValues(alpha: 0.8);
      canvas.drawCircle(Offset(math.cos(a) * d, math.sin(a) * d), 1.5 + rnd.nextDouble() * r * 0.06, p);
    }
  }

  static const _arrows = {'\u2191': -math.pi / 2, '\u2193': math.pi / 2, '\u2190': math.pi, '\u2192': 0.0};

  void _drawLabel(Canvas canvas, GameButton b, double r) {
    if (b.label.isEmpty || r < 14) return;
    final dark = b.colour.color.computeLuminance() > 0.45 && !b.spent;
    final ink = dark ? const Color(0xFF1B1720) : BP.paper;
    final arrow = _arrows[b.label];
    if (arrow != null) {
      canvas.save();
      canvas.rotate(arrow);
      final s = r * 0.42;
      canvas.drawPath(
        Path()
          ..moveTo(-s * 0.9, 0)
          ..lineTo(s * 0.55, 0)
          ..moveTo(s * 0.05, -s * 0.6)
          ..lineTo(s * 0.7, 0)
          ..lineTo(s * 0.05, s * 0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      );
      canvas.restore();
      return;
    }
    final size = math.min(wide ? 30.0 : 26.0, r * (b.label.length > 5 ? 0.24 : (b.label.length > 3 ? 0.3 : 0.46)));
    final style = BP.d(size, color: ink, weight: FontWeight.w800, spacing: 0.5).copyWith(
      shadows: dark ? null : [const Shadow(color: Color(0x55000000), offset: Offset(0, 1.5), blurRadius: 2)],
    );
    _text(canvas, b.label, Offset.zero, style, maxWidth: r * 1.75, maxLines: 1);
  }

  // --- Timer ring ------------------------------------------------------------

  Color _timerColour(double f, bool calm) {
    if (calm) return BP.calm;
    if (f > 0.5) return BP.paper;
    if (f > 0.25) return Color.lerp(BP.amber, BP.paper, (f - 0.25) / 0.25)!;
    return Color.lerp(BP.signal, BP.amber, f / 0.25)!;
  }

  /// The countdown, drawn as a draining ring hugging the button (following
  /// its shape, size and position), heating up and pulsing near the end.
  void _drawTimerRing(Canvas canvas, GameButton b, Offset centre, double r, double f, bool calm, double pop) {
    final stroke = (r * 0.075).clamp(3.5, 8.0);
    final gap = (r * 0.13).clamp(7.0, 16.0) + stroke / 2;
    final colour = _timerColour(f, calm);
    final urgent = !calm && f < 0.3;
    final pulse = urgent ? math.pow(math.sin(_time * (8 + (0.3 - f) * 40)), 2).toDouble() : 0.0;
    final width = stroke * (1 + pulse * 0.35);
    final ringCentre = centre + Offset(0, math.max(5.0, r * 0.16) * 0.35);

    final Path track;
    final Path arc;
    if (b.shape == ButtonShape.key) {
      final rr = RRect.fromRectAndRadius(_keyRect(ringCentre, r).inflate(gap), Radius.circular(r * 0.3 + gap));
      track = _rrectFromTop(rr);
      final metric = track.computeMetrics().first;
      arc = metric.extractPath(0, metric.length * f);
    } else {
      final rect = Rect.fromCircle(center: ringCentre, radius: r + gap);
      track = Path()..addOval(rect);
      arc = Path()..addArc(rect, -math.pi / 2, math.pi * 2 * f);
    }
    final alpha = pop.clamp(0.0, 1.0);
    canvas.drawPath(track, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = BP.paper.withValues(alpha: 0.07 * alpha));
    if (f <= 0) return;
    if (urgent) {
      canvas.drawPath(arc, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2.6
        ..strokeCap = StrokeCap.round
        ..color = colour.withValues(alpha: 0.35 * alpha * (0.5 + pulse * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    }
    canvas.drawPath(arc, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = colour.withValues(alpha: alpha));
    // A bright bead on the draining end.
    final metric = arc.computeMetrics().firstOrNull;
    final tangent = metric?.getTangentForOffset(metric.length);
    if (tangent != null) {
      canvas.drawCircle(tangent.position, width * 0.85, Paint()..color = BP.tint(colour, 0.6).withValues(alpha: alpha));
    }
  }

  Path _rrectFromTop(RRect rr) {
    final rad = rr.tlRadiusX;
    return Path()
      ..moveTo(rr.center.dx, rr.top)
      ..lineTo(rr.right - rad, rr.top)
      ..arcToPoint(Offset(rr.right, rr.top + rad), radius: Radius.circular(rad))
      ..lineTo(rr.right, rr.bottom - rad)
      ..arcToPoint(Offset(rr.right - rad, rr.bottom), radius: Radius.circular(rad))
      ..lineTo(rr.left + rad, rr.bottom)
      ..arcToPoint(Offset(rr.left, rr.bottom - rad), radius: Radius.circular(rad))
      ..lineTo(rr.left, rr.top + rad)
      ..arcToPoint(Offset(rr.left + rad, rr.top), radius: Radius.circular(rad))
      ..close();
  }

  /// Grids get one clock: a frame around all their buttons.
  void _drawFrameTimer(Canvas canvas, Round round, double f, double exit) {
    final vis = round.buttons.where((b) => b.visible).toList();
    if (vis.isEmpty || round.verdict != Verdict.pending) return;
    var box = Rect.zero;
    for (final b in vis) {
      final c = _toScreen(b);
      final rr = Rect.fromCircle(center: c, radius: _radius(b));
      box = box == Rect.zero ? rr : box.expandToInclude(rr);
    }
    final rr = RRect.fromRectAndRadius(box.inflate(18), const Radius.circular(26));
    final path = _rrectFromTop(rr);
    final metric = path.computeMetrics().first;
    final colour = _timerColour(f, false);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = BP.paper.withValues(alpha: 0.07));
    canvas.drawPath(metric.extractPath(0, metric.length * f), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = f < 0.3 ? 6 + math.pow(math.sin(_time * 12), 2) * 2 : 5
      ..strokeCap = StrokeCap.round
      ..color = colour.withValues(alpha: 1 - exit));
  }

  // --- Fake overlays ---------------------------------------------------------

  void _drawOverlay(Canvas canvas, FakeOverlay o, Round round) {
    switch (o.kind) {
      case FakeKind.loading:
        _drawLoading(canvas, o, round);
      case FakeKind.win:
        _drawWin(canvas, o, round);
      case FakeKind.notification:
        _drawNotification(canvas, o);
    }
  }

  void _drawLoading(Canvas canvas, FakeOverlay o, Round round) {
    final screen = Offset.zero & _screen;
    canvas.drawRect(screen, Paint()..color = BP.ink.withValues(alpha: 0.93));
    final c = playRect.center;
    // Spinner.
    final a = _time * 5;
    canvas.drawArc(
      Rect.fromCircle(center: c - const Offset(0, 46), radius: 20),
      a,
      math.pi * 1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = BP.paper,
    );
    _text(canvas, o.title, c + const Offset(0, 4), BP.t(18, weight: FontWeight.w700), maxWidth: 320);
    final bar = Rect.fromCenter(center: c + const Offset(0, 44), width: 240, height: 6);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)), Paint()..color = BP.line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * o.progress, bar.height), const Radius.circular(3)),
      Paint()..color = BP.paper,
    );
    _text(canvas, o.body, c + const Offset(0, 72), BP.t(13, color: BP.muted), maxWidth: 300);
  }

  void _drawWin(Canvas canvas, FakeOverlay o, Round round) {
    final r = _overlayRect(o.rect);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(28));
    canvas.drawRRect(rr.shift(const Offset(0, 14)), Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
    canvas.drawRRect(rr, Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [const Color(0xFFFFE08A), const Color(0xFFFFA62B)]));
    canvas.save();
    canvas.clipRRect(rr);
    final rng = math.Random(7);
    for (var i = 0; i < 26; i++) {
      final x = r.left + rng.nextDouble() * r.width;
      final y = r.top + ((rng.nextDouble() * r.height + round.elapsed * (50 + rng.nextDouble() * 70)) % r.height);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(round.elapsed * 3 + i);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 7, height: 11), Paint()..color = GameColour.all[i % 6].color);
      canvas.restore();
    }
    canvas.restore();
    _text(canvas, o.title, Offset(r.center.dx, r.top + r.height * 0.3), BP.d(wide ? 34 : 26, color: const Color(0xFF3A1D00)), maxWidth: r.width - 32);
    _text(canvas, o.body, Offset(r.center.dx, r.top + r.height * 0.52), BP.t(16, color: const Color(0xFF5C3300), weight: FontWeight.w700), maxWidth: r.width - 32);
    if (o.buttonLabel != null) {
      final btn = Rect.fromCenter(center: Offset(r.center.dx, r.top + r.height * 0.76), width: math.min(260, r.width - 48), height: 54);
      canvas.drawRRect(RRect.fromRectAndRadius(btn.shift(const Offset(0, 4)), const Radius.circular(27)), Paint()..color = const Color(0xFF1C1206));
      canvas.drawRRect(RRect.fromRectAndRadius(btn, const Radius.circular(27)), Paint()..color = const Color(0xFF2B1C0A));
      _text(canvas, o.buttonLabel!, btn.center, BP.d(15, color: const Color(0xFFFFD36B), spacing: 1));
    }
  }

  void _drawNotification(Canvas canvas, FakeOverlay o) {
    final r = _overlayRect(o.rect);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(wide ? 14 : 22));
    canvas.drawRRect(rr.shift(const Offset(0, 8)), Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
    final light = !wide;
    canvas.drawRRect(rr, Paint()..color = light ? const Color(0xF7F4F3F8) : const Color(0xF2262330));
    if (!light) {
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x22FFFFFF));
    }
    final iconSize = math.min(40.0, r.height * 0.5);
    final icon = Rect.fromLTWH(r.left + 16, r.center.dy - iconSize / 2, iconSize, iconSize);
    canvas.drawRRect(RRect.fromRectAndRadius(icon, Radius.circular(iconSize * 0.24)), Paint()..color = const Color(0xFF34C759));
    canvas.drawCircle(icon.center, iconSize * 0.22, Paint()..color = const Color(0xFFFFFFFF));
    final textLeft = icon.right + 14;
    final width = r.right - textLeft - 56;
    final title = _tp(TextSpan(text: o.title, style: BP.t(16, color: light ? const Color(0xFF111111) : BP.paper, weight: FontWeight.w800, height: 1.2)), width, maxLines: 1, align: TextAlign.left);
    final body = _tp(TextSpan(text: o.body, style: BP.t(14, color: light ? const Color(0xFF4A4A4A) : BP.muted, height: 1.2)), width, maxLines: 1, align: TextAlign.left);
    title.paint(canvas, Offset(textLeft, r.center.dy - title.height - 1));
    body.paint(canvas, Offset(textLeft, r.center.dy + 2));
    final now = _tp(TextSpan(text: 'now', style: BP.t(12, color: light ? const Color(0xFF8A8A8A) : BP.faint)), 60);
    now.paint(canvas, Offset(r.right - now.width - 16, r.top + 12));
  }

  // --- Feedback --------------------------------------------------------------

  void _drawStamp(Canvas canvas) {
    final t = (_stampAge / 0.7).clamp(0.0, 1.0);
    final inT = easeOutBack((_stampAge / 0.22).clamp(0.0, 1.0));
    final alpha = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4);
    final c = instructionRect.center;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.06);
    canvas.scale(1.5 - 0.5 * inT);
    final style = BP.d(wide ? 44 : 34, color: BP.mint.withValues(alpha: alpha), spacing: 2).copyWith(
      shadows: [Shadow(color: BP.mint.withValues(alpha: 0.5 * alpha), blurRadius: 18)],
    );
    // Cover the instruction while the stamp is up.
    final tp = _tp(TextSpan(text: _stamp, style: style), 600, maxLines: 1);
    final bg = Rect.fromCenter(center: Offset.zero, width: tp.width + 40, height: tp.height + 18);
    canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(14)), Paint()..color = BP.ink.withValues(alpha: 0.92 * alpha));
    canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(14)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = BP.mint.withValues(alpha: 0.7 * alpha));
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _drawFailFlash(Canvas canvas, Rect screen) {
    final t = (_failAge / 0.6).clamp(0.0, 1.0);
    final a = (1 - t) * (1 - t);
    canvas.drawRect(
      screen,
      Paint()
        ..shader = ui.Gradient.radial(
          screen.center,
          math.max(screen.width, screen.height) * 0.7,
          [const Color(0x00000000), BP.signal.withValues(alpha: 0.55 * a)],
          [0.35, 1],
        ),
    );
    if (_failAge < 0.06) canvas.drawRect(screen, Paint()..color = const Color(0x33FFFFFF));
  }

  void _drawBanner(Canvas canvas) {
    final alarm = game.bannerIsAlarm;
    final age = game.bannerDuration - game.bannerTime;
    final inT = easeOutBack((age / 0.3).clamp(0.0, 1.0));
    final out = (game.bannerTime / 0.25).clamp(0.0, 1.0);
    final title = _tp(TextSpan(text: game.banner, style: BP.d(alarm ? 26 : 18, spacing: 1.5)), _screen.width - 60, maxLines: 1);
    final sub = game.bannerSub.isEmpty
        ? null
        : _tp(TextSpan(text: game.bannerSub, style: BP.t(13, color: BP.paper.withValues(alpha: 0.85), weight: FontWeight.w700)), _screen.width - 60, maxLines: 1);
    final w = math.max(title.width, sub?.width ?? 0) + 48;
    final h = title.height + (sub == null ? 0 : sub.height + 4) + 24;
    final top = hudHeight + 10 - (1 - inT) * 40 - (1 - out) * 20;
    final rect = Rect.fromCenter(center: Offset(_screen.width / 2, top + h / 2), width: w, height: h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h / 2.4));
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(255, 255, 255, out));
    canvas.drawRRect(rr.shift(const Offset(0, 8)), Paint()
      ..color = const Color(0x88000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawRRect(rr, Paint()..color = alarm ? BP.signal : BP.surfaceHi);
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..color = alarm ? const Color(0x55FFFFFF) : BP.line);
    title.paint(canvas, Offset(rect.center.dx - title.width / 2, rect.top + 12));
    sub?.paint(canvas, Offset(rect.center.dx - sub.width / 2, rect.top + 12 + title.height + 4));
    canvas.restore();
  }
}
