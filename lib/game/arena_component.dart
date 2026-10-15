import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../logic/run_engine.dart';
import '../rounds/round.dart';
import 'button_panic_game.dart';

/// Draws everything during play: HUD, instruction, timer, buttons, fake
/// overlays and banners, with the chaos layers (shake, rotation, inversion)
/// applied on top. It also turns a screen point into "what was tapped",
/// undoing the same chaos transforms so taps land where things look.
class ArenaComponent extends Component with HasGameReference<ButtonPanicGame> {
  static const double maxColumnWidth = 520;
  static const double hudHeight = 48;

  Size get _screen => Size(game.size.x, game.size.y);

  Rect get columnRect {
    final s = _screen;
    final w = math.min(s.width, maxColumnWidth);
    return Rect.fromLTWH((s.width - w) / 2, 0, w, s.height);
  }

  double get _instructionHeight => math.max(112, _screen.height * 0.19);

  Rect get instructionRect {
    final c = columnRect;
    return Rect.fromLTWH(c.left + 16, hudHeight, c.width - 32, _instructionHeight);
  }

  Rect get timerRect {
    final i = instructionRect;
    return Rect.fromLTWH(i.left, i.bottom + 4, i.width, 10);
  }

  /// Where buttons live. Positions in rounds are 0..1 inside this rect.
  Rect get playRect {
    final c = columnRect;
    final top = timerRect.bottom + 12;
    return Rect.fromLTRB(c.left + 10, top, c.right - 10, math.max(top + 100, _screen.height - 16));
  }

  double get _unit => math.min(playRect.width, playRect.height);

  Offset _toScreen(double x, double y) {
    final p = playRect;
    return Offset(p.left + x * p.width, p.top + y * p.height);
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

  // ---------------------------------------------------------------------------
  // Hit testing
  // ---------------------------------------------------------------------------

  /// Undo shake and rotation so we test against where things are drawn.
  Offset _untransform(Offset p) {
    final c = _screen.center(Offset.zero);
    final q = p - game.shakeOffset - c;
    final a = -game.rotation;
    return Offset(q.dx * math.cos(a) - q.dy * math.sin(a), q.dx * math.sin(a) + q.dy * math.cos(a)) + c;
  }

  /// Returns the id of the overlay or button under [screenPoint], or null.
  String? hitTest(Offset screenPoint, Round round) {
    final p = _untransform(screenPoint);
    for (final o in round.overlays.reversed) {
      if (!o.blocksInput) continue;
      if (_overlayRect(o.rect).contains(p)) return o.id;
    }
    for (final b in round.buttons.reversed) {
      if (!b.visible) continue;
      final centre = _toScreen(b.x, b.y);
      final r = b.radius * _unit;
      // A little forgiveness for fat fingers and tiny shrinking buttons.
      if ((p - centre).distance <= r * 1.1 + 6) return b.id;
    }
    return null;
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
    final round = game.round;
    if (round == null) return;
    final screen = Offset.zero & _screen;
    final chaos = game.chaos;
    final invert = (chaos.invert && game.phase != GamePhase.roundWon) || game.flashInvert > 0;

    if (invert) {
      canvas.saveLayer(screen, Paint()..colorFilter = const ColorFilter.matrix(_invertMatrix));
    } else {
      canvas.save();
    }

    // Background (calm rounds get a soft blue, suspiciously nice).
    canvas.drawRect(screen, Paint()..color = chaos.calm ? const Color(0xFF16263A) : const Color(0xFF111117));

    canvas.save();
    final c = _screen.center(Offset.zero);
    canvas.translate(game.shakeOffset.dx + c.dx, game.shakeOffset.dy + c.dy);
    canvas.rotate(game.rotation);
    canvas.translate(-c.dx, -c.dy);

    _drawHud(canvas, round);
    _drawInstruction(canvas, round);
    if (round.showTimer) _drawTimer(canvas, round);
    for (final b in round.buttons) {
      if (b.visible) _drawButton(canvas, b);
    }
    for (final o in round.overlays) {
      _drawOverlay(canvas, o, round);
    }
    if (game.phase == GamePhase.roundWon) _drawSuccess(canvas);
    canvas.restore();

    if (game.bannerTime > 0 && game.banner.isNotEmpty) _drawBanner(canvas);
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String text,
    Offset centre, {
    double size = 20,
    Color color = const Color(0xFFFFFFFF),
    FontWeight weight = FontWeight.w800,
    double maxWidth = 400,
    double letterSpacing = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight, letterSpacing: letterSpacing, height: 1.1),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawHud(Canvas canvas, Round round) {
    final col = columnRect;
    final e = game.engine;
    const dim = Color(0x99FFFFFF);
    _text(
      canvas,
      'ROUND ${round.ctx.roundIndex + 1}',
      Offset(col.left + 70, hudHeight / 2),
      size: 15,
      color: dim,
      letterSpacing: 1.5,
      maxWidth: 140,
    );
    final modeText = e?.mode == GameMode.daily ? 'DAILY' : (game.isPractice ? 'PRACTICE' : 'ENDLESS');
    _text(
      canvas,
      modeText,
      Offset(col.right - 60, hudHeight / 2),
      size: 13,
      color: dim,
      letterSpacing: 2,
      maxWidth: 120,
      weight: FontWeight.w600,
    );
    final layers = game.chaos.activeLayers.where((l) => l != 'calm').toList();
    if (layers.isNotEmpty) {
      _text(
        canvas,
        layers.map((l) => l.toUpperCase()).join(' · '),
        Offset(col.center.dx, hudHeight / 2),
        size: 10,
        color: const Color(0x66FF6E40),
        letterSpacing: 1.2,
        maxWidth: 180,
        weight: FontWeight.w700,
      );
    }
  }

  void _drawInstruction(Canvas canvas, Round round) {
    final r = instructionRect;
    final calm = round.isCalm;
    final hint = round.hint;
    _text(
      canvas,
      round.instruction,
      Offset(r.center.dx, r.center.dy - (hint.isEmpty ? 0 : 12)),
      size: calm ? 36 : (round.instruction.length > 26 ? 26 : 34),
      maxWidth: r.width,
      weight: calm ? FontWeight.w300 : FontWeight.w900,
      color: calm ? const Color(0xFFB9D7F0) : const Color(0xFFFFFFFF),
    );
    if (hint.isNotEmpty) {
      _text(
        canvas,
        hint,
        Offset(r.center.dx, r.bottom - 14),
        size: 15,
        maxWidth: r.width,
        weight: FontWeight.w500,
        color: const Color(0x99FFFFFF),
      );
    }
  }

  void _drawTimer(Canvas canvas, Round round) {
    final r = timerRect;
    final f = round.timeLimit <= 0 ? 0.0 : (round.timeLeft / round.timeLimit).clamp(0.0, 1.0);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = const Color(0x22FFFFFF));
    final colour = f > 0.5
        ? Color.lerp(const Color(0xFFFDD835), const Color(0xFF43A047), (f - 0.5) * 2)!
        : Color.lerp(const Color(0xFFE53935), const Color(0xFFFDD835), f * 2)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width * f, r.height), const Radius.circular(5)),
      Paint()..color = game.chaos.calm ? const Color(0xFF7FB3D5) : colour,
    );
  }

  void _drawButton(Canvas canvas, GameButton b) {
    final centre = _toScreen(b.x, b.y);
    final r = b.radius * _unit;
    if (r < 1) return;
    final depth = math.max(3.0, r * 0.1);
    final base = b.colour.color;
    final shadow = Color.lerp(base, const Color(0xFF000000), 0.45)!;
    final pressedShift = b.pressed ? depth * 0.8 : 0.0;

    if (b.highlighted) {
      canvas.drawCircle(
        centre,
        r * 1.28,
        Paint()
          ..color = base.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }
    canvas.drawCircle(centre + Offset(0, depth), r, Paint()..color = shadow);
    final face = b.highlighted ? Color.lerp(base, const Color(0xFFFFFFFF), 0.45)! : base;
    canvas.drawCircle(centre + Offset(0, pressedShift), r, Paint()..color = face);
    // Shine.
    canvas.drawCircle(
      centre + Offset(-r * 0.3, -r * 0.35 + pressedShift),
      r * 0.32,
      Paint()..color = const Color(0x2EFFFFFF),
    );
    if (b.ring > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r + 10),
        -math.pi / 2,
        math.pi * 2 * b.ring,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFFFFF),
      );
    }
    if (b.label.isNotEmpty && r > 14) {
      final dark = b.colour == GameColour.yellow;
      _text(
        canvas,
        b.label,
        centre + Offset(0, pressedShift),
        size: math.min(30, r * (b.label.length > 4 ? 0.34 : 0.5)),
        color: dark ? const Color(0xFF222222) : const Color(0xFFFFFFFF),
        maxWidth: r * 1.8,
        letterSpacing: 1,
      );
    }
  }

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
    canvas.drawRect(screen, Paint()..color = const Color(0xD80B0B10));
    final c = playRect.center;
    final spin = round.elapsed * 6;
    canvas.drawArc(
      Rect.fromCircle(center: c - const Offset(0, 40), radius: 26),
      spin,
      math.pi * 1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFFFFF),
    );
    _text(canvas, o.title, c + const Offset(0, 20), size: 20, weight: FontWeight.w600, maxWidth: 320);
    final bar = Rect.fromCenter(center: c + const Offset(0, 58), width: 220, height: 8);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(4)), Paint()..color = const Color(0x33FFFFFF));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bar.left, bar.top, bar.width * o.progress, bar.height),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF1E88E5),
    );
    _text(canvas, o.body, c + const Offset(0, 84), size: 13, weight: FontWeight.w400, color: const Color(0x88FFFFFF));
  }

  void _drawWin(Canvas canvas, FakeOverlay o, Round round) {
    final r = _overlayRect(o.rect);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(24));
    canvas.drawRRect(
      rr,
      Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, const [Color(0xFFFFD54F), Color(0xFFFF8F00)]),
    );
    // Confetti.
    final rng = math.Random(3);
    for (var i = 0; i < 40; i++) {
      final x = r.left + rng.nextDouble() * r.width;
      final y = r.top + ((rng.nextDouble() * r.height + round.elapsed * (40 + rng.nextDouble() * 60)) % r.height);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: 6, height: 10),
        Paint()..color = GameColour.all[i % GameColour.all.length].color,
      );
    }
    _text(
      canvas,
      o.title,
      Offset(r.center.dx, r.top + r.height * 0.28),
      size: 34,
      color: const Color(0xFF3E2000),
      maxWidth: r.width - 24,
    );
    _text(
      canvas,
      o.body,
      Offset(r.center.dx, r.top + r.height * 0.5),
      size: 16,
      weight: FontWeight.w600,
      color: const Color(0xFF5D3300),
      maxWidth: r.width - 24,
    );
    if (o.buttonLabel != null) {
      final btn = Rect.fromCenter(
        center: Offset(r.center.dx, r.top + r.height * 0.76),
        width: math.min(240, r.width - 40),
        height: 52,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(btn, const Radius.circular(26)),
        Paint()..color = const Color(0xFF2E7D32),
      );
      _text(canvas, o.buttonLabel!, btn.center, size: 18, letterSpacing: 1);
    }
  }

  void _drawNotification(Canvas canvas, FakeOverlay o) {
    final r = _overlayRect(o.rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.shift(const Offset(0, 4)), const Radius.circular(18)),
      Paint()..color = const Color(0x55000000),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(18)), Paint()..color = const Color(0xF2F2F2F7));
    final icon = Rect.fromLTWH(r.left + 14, r.center.dy - 18, 36, 36);
    canvas.drawRRect(RRect.fromRectAndRadius(icon, const Radius.circular(9)), Paint()..color = const Color(0xFF34C759));
    final textLeft = icon.right + 12;
    final width = r.right - textLeft - 12;
    final title = TextPainter(
      text: TextSpan(
        text: o.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111111)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    final body = TextPainter(
      text: TextSpan(
        text: o.body,
        style: const TextStyle(fontSize: 14, color: Color(0xFF444444)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    title.paint(canvas, Offset(textLeft, r.center.dy - title.height));
    body.paint(canvas, Offset(textLeft, r.center.dy + 2));
    _text(
      canvas,
      'now',
      Offset(r.right - 26, r.top + 16),
      size: 11,
      weight: FontWeight.w400,
      color: const Color(0xFF888888),
    );
  }

  void _drawSuccess(Canvas canvas) {
    final p = playRect;
    canvas.drawRect(p, Paint()..color = const Color(0x2243A047));
    const words = ['NICE', 'OK', 'PHEW', 'YES', 'SURVIVED', 'FINE'];
    final i = (game.engine?.roundIndex ?? 0) % words.length;
    _text(canvas, words[i], p.center, size: 44, color: const Color(0xFF69F0AE), letterSpacing: 3);
  }

  void _drawBanner(Canvas canvas) {
    // Sits over the HUD at the very top so it never hides the buttons.
    final alarm = game.bannerIsAlarm;
    final fade = (game.bannerTime / 0.3).clamp(0.0, 1.0);
    final band = Rect.fromLTWH(0, 0, _screen.width, game.bannerSub.isEmpty ? 56 : 72);
    final bg = alarm ? const Color(0xFFD50000) : const Color(0xFF2A2A40);
    canvas.drawRect(band, Paint()..color = bg.withValues(alpha: 0.94 * fade));
    _text(
      canvas,
      game.banner,
      Offset(band.center.dx, band.top + (game.bannerSub.isEmpty ? 28 : 26)),
      size: alarm ? 32 : 24,
      letterSpacing: 3,
      maxWidth: _screen.width - 20,
      color: const Color(0xFFFFFFFF).withValues(alpha: fade),
    );
    if (game.bannerSub.isNotEmpty) {
      _text(
        canvas,
        game.bannerSub,
        Offset(band.center.dx, band.bottom - 13),
        size: 13,
        weight: FontWeight.w600,
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.85 * fade),
        maxWidth: _screen.width - 20,
      );
    }
  }
}
