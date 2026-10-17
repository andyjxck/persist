import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../logic/run_engine.dart';
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
  Rect get bannerRect => layout.bannerRect(_hudWidth(game.round));

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


  // Inverting by drawing white over everything in "difference" mode: one
  // fill, instead of a full-screen layer with a colour filter (the layer was
  // the single most expensive thing on a phone, and it left the paper
  // background un-inverted, so inverted text vanished into it).
  final Paint _invertPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..blendMode = BlendMode.difference;

  @override
  void render(Canvas canvas) {
    final screen = Offset.zero & _screen;
    final round = game.round;
    final calm = game.chaos.calm && round != null;
    final chaos = game.chaos;
    // Never invert a round whose answer is a colour: it makes the screen lie.
    final colourSafe = round?.allowInvert ?? true;
    final invert = round != null && colourSafe && ((chaos.invert && game.phase == GamePhase.playing) || game.flashInvert > 0);
    if (invert && !calm) canvas.drawRect(screen, _bgPaint..color = BP.ink);
    _drawBackground(canvas, screen, calm, round);
    if (round == null) return;

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

    if (game.blackout > 0 && game.phase == GamePhase.playing) _drawBlackout(canvas, screen);
    final down = game.phase == GamePhase.failing || game.phase == GamePhase.fakeGameOver || game.phase == GamePhase.gameOver;
    if (down && _failAge < 99) _drawFailFlash(canvas, screen);
    if (game.bannerShowing) _drawBanner(canvas);
    if (invert) canvas.drawRect(screen, _invertPaint);
  }

  /// The lights cut out: a dead black screen with a few lines of static.
  void _drawBlackout(Canvas canvas, Rect screen) {
    canvas.drawRect(screen.inflate(20), _fill..color = const Color(0xFF0A0A0A));
    final rnd = math.Random((_time * 60).floor());
    for (var k = 0; k < 6; k++) {
      final y = screen.top + rnd.nextDouble() * screen.height;
      canvas.drawRect(Rect.fromLTWH(screen.left, y, screen.width, 1.5 + rnd.nextDouble() * 3), _fill..color = const Color(0xFF3A3A3A));
    }
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

  /// Cream paper. As the round's clock drains, a pink-red flood rises from
  /// the bottom of the screen with a hard black waterline that jolts on every
  /// beat. Calm rounds are cold blue-grey and never flood. Two rects and a
  /// line a frame: cheap on any phone.
  void _drawBackground(Canvas canvas, Rect screen, bool calm, Round? round) {
    if (calm) {
      canvas.drawRect(screen, _bgPaint..color = BP.calmBg);
      return;
    }
    if (round == null) return;
    final f = game.phase == GamePhase.playing ? _timeLeft(round) : (game.phase == GamePhase.roundWon ? 1.0 : 1 - _floodSeen);
    final runPush = math.min(0.12, round.ctx.roundIndex * 0.006);
    final level = ((1 - f) * 0.78 + runPush).clamp(0.0, 0.9);
    _floodSeen = 1 - f;
    if (level <= 0.002) return;
    final jolt = _pulse * 6;
    final y = screen.bottom - screen.height * level - jolt;
    canvas.drawRect(Rect.fromLTRB(screen.left, y, screen.right, screen.bottom), _bgPaint..color = BP.flood);
    canvas.drawLine(Offset(screen.left, y), Offset(screen.right, y), _bgLine);
  }

  double _floodSeen = 0;
  final Paint _bgPaint = Paint();
  final Paint _bgLine = Paint()
    ..color = BP.paper
    ..strokeWidth = 4;

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

  /// The HUD: a black bar across the top with hazard tape under it. On the
  /// left a quiet ROUND label and the number on a hazard tag; on the wide
  /// stage the mode (or MUTED) sits on the right, inside the same width so
  /// announcements keep their room.
  void _drawHud(Canvas canvas, Round round) {
    final barH = hudHeight - 12;
    final bar = Rect.fromLTWH(-40, -40, _screen.width + 80, barH + 40);
    canvas.drawRect(bar, _fill..color = BP.paper);
    _drawTape(canvas, Rect.fromLTWH(-40, barH, _screen.width + 80, 8));
    canvas.drawRect(Rect.fromLTWH(-40, barH, _screen.width + 80, 1.5), _fill..color = BP.paper);

    final (label, number, practice) = _hudParts(round);
    final midY = barH / 2;
    var x = columnRect.left + _pad;
    label.paint(canvas, Offset(x, midY - label.height / 2 + 1));
    x += label.width + 8;
    final tag = Rect.fromLTWH(x, midY - number.height / 2 - 1, number.width + 14, number.height + 2);
    canvas.drawRRect(RRect.fromRectAndRadius(tag, const Radius.circular(5)), _fill..color = BP.hazard);
    number.paint(canvas, Offset(x + 7, midY - number.height / 2));
    x = tag.right + 10;
    if (practice != null) {
      final chip = Rect.fromLTWH(x, midY - practice.height / 2 - 4, practice.width + 14, practice.height + 8);
      canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(4)), _stroke
        ..strokeWidth = 1.5
        ..color = BP.onInk);
      practice.paint(canvas, Offset(x + 7, midY - practice.height / 2));
    }

    if (wide) {
      final width = _hudWidth(round);
      final muted = !game.audio.enabled;
      final mode = game.engine?.mode == GameMode.daily ? 'DAILY' : 'ENDLESS';
      var tp = _tp(TextSpan(text: muted ? '$mode  \u00b7  MUTED' : mode, style: BP.label(11, color: muted ? BP.signal : BP.onInk)), 400, maxLines: 1, align: TextAlign.left);
      if (tp.width > width && muted) {
        tp = _tp(TextSpan(text: 'MUTED', style: BP.label(11, color: BP.signal)), 400, maxLines: 1, align: TextAlign.left);
      }
      if (tp.width <= width) tp.paint(canvas, Offset(columnRect.right - _pad - tp.width, midY - tp.height / 2));
    }
  }

  (TextPainter, TextPainter, TextPainter?) _hudParts(Round? round) {
    final n = ((round?.ctx.roundIndex ?? 0) + 1).toString().padLeft(2, '0');
    final label = _tp(TextSpan(text: 'ROUND', style: BP.label(wide ? 12 : 11, color: BP.onInk)), 200, maxLines: 1, align: TextAlign.left);
    final number = _tp(TextSpan(text: n, style: BP.d(wide ? 26 : 22, color: BP.paper, spacing: 1)), 200, maxLines: 1, align: TextAlign.left);
    final practice = game.isPractice
        ? _tp(TextSpan(text: 'PRACTICE', style: BP.label(10, color: BP.onInk)), 200, maxLines: 1, align: TextAlign.left)
        : null;
    return (label, number, practice);
  }

  /// How wide the round number block is, for the announcement strip.
  double _hudWidth(Round? round) {
    final (label, number, practice) = _hudParts(round);
    var w = label.width + 8 + number.width + 14;
    if (practice != null) w += 10 + practice.width + 14;
    return w;
  }

  /// Diagonal black and yellow hazard stripes filling [r].
  void _drawTape(Canvas canvas, Rect r) {
    canvas.save();
    canvas.clipRect(r);
    canvas.drawRect(r, _fill..color = BP.hazard);
    final step = r.height * 2.2;
    final path = Path();
    for (var x = r.left - r.height; x < r.right + r.height; x += step) {
      path
        ..moveTo(x, r.bottom)
        ..lineTo(x + step / 2, r.bottom)
        ..lineTo(x + step / 2 + r.height, r.top)
        ..lineTo(x + r.height, r.top)
        ..close();
    }
    canvas.drawPath(path, _fill..color = BP.paper);
    canvas.restore();
  }

  // --- Instruction -------------------------------------------------------------

  static const _negations = {"DON'T", 'NOT', 'NEVER', 'NO', 'BOTH', 'EVERY'};

  /// Key words get a highlighter-marker block behind them: negations in
  /// red, colour names in their own colour (so YELLOW is readable on paper).
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
      final last = i == words.length - 1;
      if (c == null) {
        spans.add(TextSpan(text: last ? w : '$w ', style: base));
      } else {
        final onLight = c.computeLuminance() > 0.45;
        spans.add(TextSpan(text: '\u2009$w\u2009', style: base.copyWith(color: onLight ? BP.paper : const Color(0xFFFFFFFF), background: Paint()..color = c)));
        if (!last) spans.add(TextSpan(text: ' ', style: base));
      }
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
    final maxSize = wide ? 52.0 : 40.0;
    final colour = (round.isCalm ? BP.calm : BP.paper).withValues(alpha: dim ? 0.25 : 1);
    TextPainter? tp;
    for (var size = maxSize; size >= 18; size -= 2) {
      final style = BP.d(size, color: colour, spacing: size * 0.01, height: 1.08);
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
    // The hint sits on a small black tag under the instruction, so it reads
    // as a footnote and never competes with the instruction itself.
    final hintTp = hint.isEmpty
        ? null
        : _tp(TextSpan(text: hint.toUpperCase(), style: BP.label(wide ? 12 : 11, color: round.isCalm ? BP.calmBg : BP.cream)), r.width - 20, maxLines: 1);
    final total = tp.height + (hintTp == null ? 0 : hintTp.height + 16);
    final top = r.center.dy - total / 2;
    tp.paint(canvas, Offset(r.center.dx - tp.width / 2, top));
    if (hintTp != null) {
      final y = top + tp.height + 10;
      final tag = Rect.fromLTWH(r.center.dx - hintTp.width / 2 - 9, y, hintTp.width + 18, hintTp.height + 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(tag, const Radius.circular(4)),
        _fill..color = round.isCalm ? BP.calm : BP.paper,
      );
      hintTp.paint(canvas, Offset(tag.left + 9, y + 3));
    }
  }

  // --- Buttons ---------------------------------------------------------------

  /// A button is a flat, solid shape: no bevel, no gloss, no glow. It sinks
  /// and darkens when pressed, and swells by a hair on each beat of the clock.
  void _drawButton(Canvas canvas, Round round, GameButton b, int index, double timeF, double exit, bool calm) {
    final centre = _toScreen(b);
    var r = _radius(b);
    if (r < 1) return;
    final s = _bfx.putIfAbsent(b.id, _ButtonFx.new);

    // A hard pop in (overshoots, then settles) and a quick shrink out. No
    // transparency layers: those were the most expensive thing on a phone.
    final inT = ((roundAge - index * 0.025) / 0.16).clamp(0.0, 1.0);
    if (inT <= 0 || exit >= 0.98) return;
    final pop = inT >= 1 ? 1.0 : 0.55 + 0.45 * easeOutBack(inT);
    final pulse = round.verdict == Verdict.pending ? _pulse : 0.0;
    r *= pop * (1 + pulse * 0.035) * (1 - exit);
    if (r < 2) return;

    if (round.ringAround(b) && round.verdict == Verdict.pending && game.phase == GamePhase.playing) {
      _drawTimerRing(canvas, b, centre, r, timeF, calm, inT);
    }

    final press = s.press.x.clamp(0.0, 1.0);
    final hover = s.hover;
    final base = b.colour.color;
    var face = b.spent ? BP.line : base;
    if (b.highlighted) face = BP.tint(face, 0.35);
    if (b.shape == ButtonShape.key) {
      _drawKeycap(canvas, b, centre, r, face, hover, press);
    } else {
      _drawRoundButton(canvas, b, centre, r, face, hover, press);
    }
  }

  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _shine = Paint()..color = const Color(0x59FFFFFF);
  static const _ground = Color(0x24000000);

  /// An arcade button: a thick black outline, a darker skirt underneath and
  /// a face that physically sinks into it when pressed, with one flat shine.
  void _drawRoundButton(Canvas canvas, GameButton b, Offset centre, double r, Color face, double hover, double press) {
    final ow = BP.outline(r);
    final depth = b.spent ? 0.0 : r * 0.16;
    final sink = depth * press;
    final top = centre.translate(0, -depth * 0.5 + sink);
    if (b.highlighted) {
      canvas.drawCircle(centre, r + ow * 2.6, _fill..color = BP.hazard);
    } else if (hover > 0.01) {
      canvas.drawCircle(centre, r + ow * 2.2, _stroke
        ..strokeWidth = ow * 0.7
        ..color = BP.paper.withValues(alpha: hover));
    }
    if (depth > 0) {
      // A hard, flat shadow on the paper so the button sits on the page.
      canvas.drawCircle(centre.translate(r * 0.08, depth * 0.5 + r * 0.1), r, _fill..color = _ground);
      final skirt = centre.translate(0, depth * 0.5);
      canvas.drawCircle(skirt, r, _fill..color = BP.shade(face, 0.42));
      canvas.drawCircle(skirt, r, _stroke
        ..strokeWidth = ow
        ..color = BP.paper);
      canvas.drawRect(Rect.fromLTRB(centre.dx - r, top.dy, centre.dx + r, skirt.dy), _fill..color = BP.shade(face, 0.42));
      canvas.drawLine(Offset(centre.dx - r, top.dy), Offset(centre.dx - r, skirt.dy), _stroke..strokeWidth = ow);
      canvas.drawLine(Offset(centre.dx + r, top.dy), Offset(centre.dx + r, skirt.dy), _stroke);
    }
    canvas.drawCircle(top, r, _fill..color = face);
    canvas.drawCircle(top, r, _stroke
      ..strokeWidth = ow
      ..color = b.spent ? BP.faint : BP.paper);
    canvas.save();
    canvas.translate(top.dx, top.dy);
    if (!b.spent) {
      canvas.drawOval(Rect.fromCenter(center: Offset(-r * 0.36, -r * 0.42), width: r * 0.5, height: r * 0.26), _shine);
    }
    // Progress fill (hold / hover / rub), rising flat from the bottom.
    if (b.ring > 0) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - ow / 2)));
      canvas.drawRect(Rect.fromLTRB(-r, r - 2 * r * b.ring, r, r), _fill..color = const Color(0x66000000));
      canvas.restore();
    }
    if (b.dust > 0.01) _drawDust(canvas, b, r);
    _drawLabel(canvas, b, r);
    canvas.restore();
  }

  void _drawKeycap(Canvas canvas, GameButton b, Offset centre, double r, Color face, double hover, double press) {
    final ow = BP.outline(r);
    final depth = b.spent ? 0.0 : r * 0.18;
    final sink = depth * press;
    final cap = _keyRect(centre, r);
    final radius = Radius.circular(r * 0.16);
    final topRect = cap.shift(Offset(0, -depth * 0.5 + sink));
    if (b.highlighted) {
      canvas.drawRRect(RRect.fromRectAndRadius(cap.inflate(ow * 2.6), radius), _fill..color = BP.hazard);
    } else if (hover > 0.01) {
      canvas.drawRRect(RRect.fromRectAndRadius(cap.inflate(ow * 2.2), radius), _stroke
        ..strokeWidth = ow * 0.7
        ..color = BP.paper.withValues(alpha: hover));
    }
    if (depth > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(cap.shift(Offset(r * 0.08, depth * 0.5 + r * 0.1)), radius), _fill..color = _ground);
      final under = RRect.fromRectAndRadius(Rect.fromLTRB(cap.left, topRect.top, cap.right, cap.bottom + depth * 0.5), radius);
      canvas.drawRRect(under, _fill..color = BP.shade(face, 0.42));
      canvas.drawRRect(under, _stroke
        ..strokeWidth = ow
        ..color = BP.paper);
    }
    final rr = RRect.fromRectAndRadius(topRect, radius);
    canvas.drawRRect(rr, _fill..color = face);
    canvas.drawRRect(rr, _stroke
      ..strokeWidth = ow
      ..color = b.spent ? BP.faint : BP.paper);
    canvas.save();
    canvas.translate(topRect.center.dx, topRect.center.dy);
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
    final size = math.min(wide ? 40.0 : 34.0, r * (b.label.length > 5 ? 0.3 : (b.label.length > 3 ? 0.38 : 0.6)));
    final style = BP.d(size, color: ink, spacing: 0.5);
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
    final stroke = (r * 0.11).clamp(6.0, 12.0);
    final gap = (r * 0.2).clamp(10.0, 22.0) + stroke / 2;
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
      ..color = BP.paper.withValues(alpha: 0.12 * appear));
    if (f <= 0) return;
    canvas.drawPath(arc, _stroke
      ..strokeWidth = stroke
      ..color = colour.withValues(alpha: appear));
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
    final rr = RRect.fromRectAndRadius(box.inflate(26), const Radius.circular(10));
    final path = _rrectFromTop(rr);
    final metric = path.computeMetrics().first;
    canvas.drawPath(path, _stroke
      ..strokeWidth = 8
      ..color = BP.paper.withValues(alpha: 0.12));
    canvas.drawPath(metric.extractPath(0, metric.length * f), _stroke
      ..strokeWidth = 8
      ..color = _timerColour(f, false).withValues(alpha: 1 - exit));
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

  /// Failing: a white frame, then the screen floods solid red.
  void _drawFailFlash(Canvas canvas, Rect screen) {
    if (_failAge < 0.05) {
      canvas.drawRect(screen, Paint()..color = const Color(0xCCFFFFFF));
      return;
    }
    final t = ((_failAge - 0.05) / 0.35).clamp(0.0, 1.0);
    canvas.drawRect(screen, Paint()..color = BP.signal.withValues(alpha: 0.92 * t));
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
    final colour = alarm ? BP.signal : const Color(0xFFF4EEE2);
    // The largest size that fits on one line (down to 8), then an ellipsis.
    TextPainter? tp;
    for (var size = alarm ? 22.0 : 20.0; size >= 12; size -= 1) {
      tp = _tp(TextSpan(text: text, style: BP.d(size, color: colour, spacing: 1)), area.width, maxLines: 1);
      if (!tp.didExceedMaxLines && tp.width <= area.width) break;
    }
    final age = game.bannerDuration - game.bannerTime;
    final alpha = math.min((age / 0.12).clamp(0.0, 1.0), (game.bannerTime / 0.2).clamp(0.0, 1.0));
    if (alpha <= 0.01) return;
    final y = area.center.dy - tp!.height / 2;
    // Fade in and out with a clip-height wipe rather than a transparency
    // layer (layers are expensive on phones).
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(area.left, area.center.dy - area.height * alpha / 2, area.right, area.center.dy + area.height * alpha / 2));
    tp.paint(canvas, Offset(area.center.dx - tp.width / 2, y));
    canvas.restore();
  }
}
