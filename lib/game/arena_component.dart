import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../rounds/round.dart';
import '../ui/theme.dart';
import 'arena_layout.dart';
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

  // Fail blackout.
  double _failAge = 99;
  double _wonAge = 99;

  bool get wide => game.wide;
  Size get _screen => Size(game.size.x, game.size.y);

  // ---------------------------------------------------------------------------
  // Layout (two tuned layouts: wide web stage, tall phone screen)
  // ---------------------------------------------------------------------------

  ArenaLayout get layout => ArenaLayout(_screen, wide: wide);
  double get _pad => layout.pad;
  double get hudHeight => layout.hudHeight;
  Rect get columnRect => layout.columnRect;
  Rect get instructionRect => layout.instructionRect;

  /// Where buttons live. Positions in rounds are 0..1 inside this rect.
  Rect get playRect => layout.playRect;

  /// Where announcements go (see [ArenaLayout.bannerRect]).
  Rect get bannerRect => layout.bannerRect(_hudTp(game.round).width);

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

  void onSuccess(Round r, String? pressedId) {
    _wonAge = 0;
  }

  void onFail(Round r, String? pressedId) {
    _failAge = 0;
  }

  @override
  void update(double dt) {
    _time += dt;
    roundAge += dt;
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
    _drawBackground(canvas, screen, calm, round);
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
    canvas.restore();

    final down = game.phase == GamePhase.failing || game.phase == GamePhase.fakeGameOver || game.phase == GamePhase.gameOver;
    if (down && _failAge < 99) _drawFailFlash(canvas, screen);
    if (game.bannerShowing) _drawBanner(canvas);
    canvas.restore();
  }

  /// How strongly the last clock beat still shows (1 on the beat, fading
  /// fast). Zero when reduce motion is on.
  double get _pulse {
    if (game.reduceMotion || game.phase != GamePhase.playing) return 0;
    return math.exp(-game.beatAge * (game.beatTight ? 20 : 11));
  }

  /// Share of the round's time left (1 for untimed rounds).
  double _timeLeft(Round? r) {
    if (r == null || !r.showTimer || r.isCalm || r.timeLimit <= 0) return 1;
    return (r.timeLeft / r.timeLimit).clamp(0.0, 1.0);
  }

  /// The void: near-black, with the only light gathered around the button.
  /// The light closes in as the round's time drains (and a little more each
  /// round of the run), and breathes with the clock.
  void _drawBackground(Canvas canvas, Rect screen, bool calm, Round? round) {
    // The game's own background is already the void; only calm rounds
    // repaint it (one less full-screen fill per frame).
    if (calm) canvas.drawRect(screen, Paint()..color = BP.calmBg);
    if (round == null) return;
    final p = playRect;
    final f = game.phase == GamePhase.playing ? _timeLeft(round) : 1.0;
    final runClose = math.min(0.3, round.ctx.roundIndex * 0.01);
    final open = (0.28 + 0.72 * f) * (1 - runClose);
    final reach = math.max(p.width, p.height) * 0.8 * open + _unit * 0.25;
    // A small pre-drawn falloff, stretched and tinted: the same soft light as
    // a full-screen radial gradient, at a fraction of the fill cost (the
    // gradient shader alone took ~12 ms a frame at 1440x900 in software).
    final strength = 0.05 + 0.035 * _pulse;
    final img = calm ? (_calmLight ??= _makeLightImage(BP.calm)) : (_light ??= _makeLightImage(BP.paper));
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCircle(center: p.center, radius: reach),
      _lightPaint..color = Color.fromRGBO(0, 0, 0, strength),
    );
  }

  ui.Image? _light;
  ui.Image? _calmLight;
  final Paint _lightPaint = Paint()..filterQuality = FilterQuality.low;

  /// [colour] at the centre fading to nothing at the edge, drawn once.
  static ui.Image _makeLightImage(Color colour) {
    const n = 128.0;
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(
      const Rect.fromLTWH(0, 0, n, n),
      Paint()..shader = ui.Gradient.radial(const Offset(n / 2, n / 2), n / 2, [colour, colour.withValues(alpha: 0)]),
    );
    return rec.endRecording().toImageSync(n.toInt(), n.toInt());
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

  /// The only chrome: the round number, small and faint, in the corner.
  void _drawHud(Canvas canvas, Round round) {
    final tp = _hudTp(round);
    tp.paint(canvas, Offset(columnRect.left + _pad, hudHeight / 2 - tp.height / 2));
  }

  TextPainter _hudTp(Round? round) {
    final n = ((round?.ctx.roundIndex ?? 0) + 1).toString().padLeft(2, '0');
    final text = game.isPractice ? '$n  PRACTICE' : n;
    return _tp(TextSpan(text: text, style: BP.label(11, color: BP.faint)), 200, maxLines: 1, align: TextAlign.left);
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

  String _instrKey = '';
  TextPainter? _instrTp;

  /// The instruction, laid out once per round (fitting the largest size in
  /// two lines is expensive, so it is cached, not redone every frame).
  TextPainter _instruction(Round round, Rect r, bool dim) {
    final key = '${round.instruction}|${r.width}|${r.height}|${round.isCalm}|$dim|${round.hint.isEmpty}';
    if (key == _instrKey && _instrTp != null) return _instrTp!;
    final maxSize = wide ? 34.0 : 26.0;
    final colour = (round.isCalm ? BP.calm : BP.paper).withValues(alpha: dim ? 0.25 : 1);
    TextPainter? tp;
    for (var size = maxSize; size >= 15; size -= 2) {
      final style = BP.d(size, color: colour, weight: FontWeight.w600, spacing: size * 0.02, height: 1.15);
      tp = TextPainter(text: TextSpan(children: _emphasise(round.instruction, style)), textAlign: TextAlign.center, textDirection: TextDirection.ltr, maxLines: 2)
        ..layout(maxWidth: r.width);
      if (!tp.didExceedMaxLines && tp.height <= r.height - (round.hint.isEmpty ? 8 : 34)) break;
    }
    _instrKey = key;
    return _instrTp = tp!;
  }

  void _drawInstruction(Canvas canvas, Round round) {
    final r = instructionRect;
    final hint = round.hint;
    final dim = game.phase == GamePhase.roundWon;
    final tp = _instruction(round, r, dim);
    final hintTp = hint.isEmpty
        ? null
        : _tp(TextSpan(text: hint, style: BP.t(wide ? 14 : 13, color: BP.faint, weight: FontWeight.w600)), r.width, maxLines: 1);
    final total = tp.height + (hintTp == null ? 0 : hintTp.height + 10);
    final top = r.center.dy - total / 2;
    tp.paint(canvas, Offset(r.center.dx - tp.width / 2, top));
    hintTp?.paint(canvas, Offset(r.center.dx - hintTp.width / 2, top + tp.height + 10));
  }

  // --- Buttons ---------------------------------------------------------------

  /// A button is a flat, solid shape: no bevel, no gloss, no glow. It sinks
  /// and darkens when pressed, and swells by a hair on each beat of the clock.
  void _drawButton(Canvas canvas, Round round, GameButton b, int index, double timeF, double exit, bool calm) {
    final centre = _toScreen(b);
    var r = _radius(b);
    if (r < 1) return;
    final s = _bfx.putIfAbsent(b.id, _ButtonFx.new);

    // A quick cut in (no bounce), a quick fade out.
    final inT = ((roundAge - index * 0.02) / 0.1).clamp(0.0, 1.0);
    final alpha = inT * (1 - exit).clamp(0.0, 1.0) * (b.spent ? 0.3 : 1.0);
    if (alpha <= 0.01) return;
    final pulse = round.verdict == Verdict.pending ? _pulse : 0.0;
    r *= (0.94 + 0.06 * inT) * (1 + pulse * 0.02) * (1 - exit * 0.05);

    if (round.ringAround(b) && round.verdict == Verdict.pending && game.phase == GamePhase.playing) {
      _drawTimerRing(canvas, b, centre, r, timeF, calm, inT);
    }

    final press = s.press.x.clamp(0.0, 1.0);
    final hover = s.hover;
    final base = b.colour.color;
    var face = b.spent ? Color.lerp(base, const Color(0xFF3A3A3A), 0.7)! : base;
    if (b.highlighted) face = BP.tint(face, 0.45);
    face = BP.shade(face, press * 0.28);
    final faded = alpha < 0.999;
    if (faded) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
    if (b.shape == ButtonShape.key) {
      _drawKeycap(canvas, b, centre, r * (1 - press * 0.04), face, hover);
    } else {
      _drawRoundButton(canvas, b, centre, r * (1 - press * 0.05), face, hover);
    }
    if (faded) canvas.restore();
  }

  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  void _drawRoundButton(Canvas canvas, GameButton b, Offset centre, double r, Color face, double hover) {
    canvas.drawCircle(centre, r, _fill..color = face);
    if (b.highlighted) {
      canvas.drawCircle(centre, r + 6, _stroke
        ..strokeWidth = 2
        ..color = BP.paper);
    } else if (hover > 0.01) {
      canvas.drawCircle(centre, r + 5, _stroke
        ..strokeWidth = 1.5
        ..color = BP.paper.withValues(alpha: 0.4 * hover));
    }
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    // Progress fill (hold / hover / rub), rising flat from the bottom.
    if (b.ring > 0) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
      canvas.drawRect(Rect.fromLTRB(-r, r - 2 * r * b.ring, r, r), _fill..color = const Color(0x4D000000));
      canvas.restore();
    }
    if (b.dust > 0.01) _drawDust(canvas, b, r);
    _drawLabel(canvas, b, r);
    canvas.restore();
  }

  void _drawKeycap(Canvas canvas, GameButton b, Offset centre, double r, Color face, double hover) {
    final cap = _keyRect(centre, r);
    final rr = RRect.fromRectAndRadius(cap, Radius.circular(r * 0.12));
    canvas.drawRRect(rr, _fill..color = face);
    if (b.highlighted || hover > 0.01) {
      canvas.drawRRect(rr.inflate(5), _stroke
        ..strokeWidth = b.highlighted ? 2 : 1.5
        ..color = BP.paper.withValues(alpha: b.highlighted ? 1 : 0.4 * hover));
    }
    canvas.save();
    canvas.translate(cap.center.dx, cap.center.dy);
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
    final ink = dark ? const Color(0xFF0A0A0A) : const Color(0xFFF2F2F2);
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
    final style = BP.d(size, color: ink, weight: FontWeight.w700, spacing: 0.5);
    _text(canvas, b.label, Offset.zero, style, maxWidth: r * 1.75, maxLines: 1);
  }

  // --- Timer ring ------------------------------------------------------------

  Color _timerColour(double f, bool calm) {
    if (calm) return BP.calm;
    return f > 0.25 ? BP.paper : BP.signal;
  }

  /// The countdown: a hairline draining around the button, following its
  /// shape. It turns red in the last quarter. No glow, no bead.
  void _drawTimerRing(Canvas canvas, GameButton b, Offset centre, double r, double f, bool calm, double appear) {
    final stroke = (r * 0.028).clamp(1.5, 3.0);
    final gap = (r * 0.16).clamp(8.0, 18.0);
    final colour = _timerColour(f, calm);
    final Path track;
    final Path arc;
    if (b.shape == ButtonShape.key) {
      final rr = RRect.fromRectAndRadius(_keyRect(centre, r).inflate(gap), Radius.circular(r * 0.12 + gap * 0.5));
      track = _rrectFromTop(rr);
      final metric = track.computeMetrics().first;
      arc = metric.extractPath(0, metric.length * f);
    } else {
      final rect = Rect.fromCircle(center: centre, radius: r + gap);
      track = Path()..addOval(rect);
      arc = Path()..addArc(rect, -math.pi / 2, math.pi * 2 * f);
    }
    canvas.drawPath(track, _stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = BP.paper.withValues(alpha: 0.06 * appear));
    if (f <= 0) return;
    canvas.drawPath(arc, _stroke
      ..strokeWidth = stroke
      ..color = colour.withValues(alpha: 0.9 * appear));
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
  /// Grids get one clock: a hairline frame around all their buttons.
  void _drawFrameTimer(Canvas canvas, Round round, double f, double exit) {
    final vis = round.buttons.where((b) => b.visible).toList();
    if (vis.isEmpty || round.verdict != Verdict.pending) return;
    var box = Rect.zero;
    for (final b in vis) {
      final c = _toScreen(b);
      final rr = Rect.fromCircle(center: c, radius: _radius(b));
      box = box == Rect.zero ? rr : box.expandToInclude(rr);
    }
    final rr = RRect.fromRectAndRadius(box.inflate(18), const Radius.circular(6));
    final path = _rrectFromTop(rr);
    final metric = path.computeMetrics().first;
    canvas.drawPath(path, _stroke
      ..strokeWidth = 2
      ..color = BP.paper.withValues(alpha: 0.06));
    canvas.drawPath(metric.extractPath(0, metric.length * f), _stroke
      ..strokeWidth = 2
      ..color = _timerColour(f, false).withValues(alpha: 0.9 * (1 - exit)));
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

  /// Failing: one pale frame, then the lights go out.
  void _drawFailFlash(Canvas canvas, Rect screen) {
    if (_failAge < 0.05) {
      canvas.drawRect(screen, Paint()..color = const Color(0x1FFFFFFF));
      return;
    }
    final t = ((_failAge - 0.05) / 0.5).clamp(0.0, 1.0);
    canvas.drawRect(screen, Paint()..color = Color.fromRGBO(0, 0, 0, 0.7 * t));
  }

  /// Announcements are a few spaced words in the empty strip at the top,
  /// clipped to it: they never cover the instruction, the timer or the
  /// button. No box, no drop-down, no movement: they fade in and out. The
  /// game holds them back while the scene is rotating (see
  /// [ButtonPanicGame.bannerShowing]).
  void _drawBanner(Canvas canvas) {
    final area = bannerRect;
    if (area.width < 24) return;
    final alarm = game.bannerIsAlarm;
    final text = game.banner.toUpperCase();
    final colour = alarm ? BP.signal : BP.muted;
    // The largest size that fits on one line (down to 8), then an ellipsis.
    TextPainter? tp;
    for (var size = alarm ? 12.0 : 10.0; size >= 8; size -= 1) {
      tp = _tp(TextSpan(text: text, style: BP.label(size, color: colour)), area.width, maxLines: 1);
      if (!tp.didExceedMaxLines && tp.width <= area.width) break;
    }
    final age = game.bannerDuration - game.bannerTime;
    final alpha = math.min((age / 0.12).clamp(0.0, 1.0), (game.bannerTime / 0.2).clamp(0.0, 1.0));
    if (alpha <= 0.01) return;
    final y = math.min(hudHeight / 2, area.bottom - tp!.height / 2) - tp.height / 2;
    canvas.save();
    canvas.clipRect(area);
    canvas.saveLayer(area, Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
    tp.paint(canvas, Offset(area.center.dx - tp.width / 2, y));
    canvas.restore();
    canvas.restore();
  }
}
