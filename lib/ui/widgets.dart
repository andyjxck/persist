import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// How a [StarkAction] looks.
enum ActionLook {
  /// A small black pill (settings toggles, the phone's sound switch).
  chip,

  /// The main action on paper: red slab, white type, hard black shadow.
  primary,

  /// Other actions: white slab, black type, hard black shadow.
  secondary,

  /// The main action on a red screen: hazard-yellow slab, black type.
  hazard,
}

/// A chunky sticker button with a thick outline and a hard offset shadow.
/// It lifts a hair under the mouse, presses down into its shadow, and shows
/// a separate black focus ring when reached with the keyboard.
class StarkAction extends StatefulWidget {
  const StarkAction({
    super.key,
    required this.label,
    required this.onTap,
    this.size = 12,
    this.color = BP.muted,
    this.semantic,
    this.look = ActionLook.secondary,
    this.keyHint,
    this.lit,
  });

  final String label;
  final VoidCallback? onTap;
  final double size;

  /// Text colour for [ActionLook.chip].
  final Color color;
  final String? semantic;
  final ActionLook look;

  /// A keyboard shortcut drawn as a little keycap inside the slab.
  final String? keyHint;

  /// Chips only: draws an on/off light before the label.
  final bool? lit;

  @override
  State<StarkAction> createState() => _StarkActionState();
}

class _StarkActionState extends State<StarkAction> {
  bool _hot = false;
  bool _focus = false;
  bool _down = false;

  Widget _focusRing(double radius) => Positioned(
    left: -5,
    top: -5,
    right: -5,
    bottom: -5,
    child: IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: BP.paper, width: 2.5),
          borderRadius: BorderRadius.circular(radius + 5),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final look = widget.look;
    final Widget body;
    if (look == ActionLook.chip) {
      final lit = widget.lit;
      body = Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _down ? BP.inkSoft : BP.paper,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (lit != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: lit ? BP.hazard : null,
                        border: lit ? null : Border.all(color: BP.onInk, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(widget.label, style: BP.label(widget.size, color: _hot ? BP.hazard : widget.color)),
                ],
              ),
            ),
            if (_focus) _focusRing(14),
          ],
        ),
      );
    } else {
      final (Color face, Color hotFace, Color ink) = switch (look) {
        ActionLook.primary => (BP.signal, BP.shade(BP.signal, 0.1), const Color(0xFFFFFFFF)),
        ActionLook.hazard => (BP.hazard, BP.tint(BP.hazard, 0.45), BP.paper),
        _ => (const Color(0xFFFFFFFF), BP.hazard, BP.paper),
      };
      final depth = widget.size < 13 ? 4.0 : 6.0;
      final sink = _down ? depth : (_hot ? -1.5 : 0.0);
      final hint = widget.keyHint;
      body = Padding(
        padding: EdgeInsets.fromLTRB(6, 6, 6 + depth, 6 + depth),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              left: depth,
              top: depth,
              right: -depth,
              bottom: -depth,
              child: Container(decoration: BoxDecoration(color: BP.paper, borderRadius: BorderRadius.circular(BP.radius))),
            ),
            Transform.translate(
              offset: Offset(sink, sink),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: widget.size * 1.4, vertical: widget.size * 0.7),
                decoration: BoxDecoration(
                  color: _hot ? hotFace : face,
                  border: Border.all(color: BP.paper, width: 3),
                  borderRadius: BorderRadius.circular(BP.radius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.label, style: BP.d(widget.size * 1.6, color: ink, spacing: 1)),
                    if (hint != null) ...[
                      SizedBox(width: widget.size * 0.7),
                      KeyCap(hint, size: (widget.size * 0.62).clamp(8.0, 11.0), dark: look != ActionLook.primary),
                    ],
                  ],
                ),
              ),
            ),
            if (_focus) _focusRing(BP.radius),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: widget.semantic ?? widget.label,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onShowHoverHighlight: (v) => setState(() => _hot = v),
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call())},
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: widget.onTap,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A little keyboard key with a label: shortcut hints.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.size = 11, this.dark = false});
  final String label;
  final double size;

  /// Black key with cream type (for light surfaces); otherwise cream key.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final face = dark ? BP.paper : BP.cream;
    final ink = dark ? BP.cream : BP.paper;
    return Container(
      padding: EdgeInsets.fromLTRB(size * 0.6, size * 0.28, size * 0.6, size * 0.22),
      decoration: BoxDecoration(
        color: face,
        border: Border.all(color: BP.paper, width: 1.5),
        borderRadius: BorderRadius.circular(size * 0.4),
        boxShadow: [BoxShadow(color: dark ? BP.shade(BP.muted, 0.2) : BP.paper, offset: const Offset(0, 2))],
      ),
      child: Text(label, style: BP.label(size, color: ink)),
    );
  }
}

/// A row of shortcut hints: a keycap, then what it does.
class KeyHints extends StatelessWidget {
  const KeyHints(this.hints, {super.key, this.color = BP.muted, this.alignment = WrapAlignment.start});
  final List<(String, String)> hints;
  final Color color;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: BP.s4,
    runSpacing: BP.s2,
    children: [
      for (final (key, what) in hints)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyCap(key, size: 10, dark: true),
            const SizedBox(width: 7),
            Text(what, style: BP.label(11, color: color)),
          ],
        ),
    ],
  );
}

/// A tilted sticker: a slab of colour with a black outline and a hard
/// shadow, for stamps such as NEW BEST.
class Sticker extends StatelessWidget {
  const Sticker({super.key, required this.label, this.size = 22, this.color = BP.hazard, this.ink = BP.paper, this.angle = -0.08});
  final String label;
  final double size;
  final Color color;
  final Color ink;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.55, vertical: size * 0.22),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: BP.paper, width: 3),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: BP.paper, offset: Offset(4, 4))],
      ),
      child: Text(label, style: BP.d(size, color: ink, spacing: 1)),
    ),
  );
}

/// Printed halftone dots over whatever is behind (one shader fill).
class Halftone extends StatelessWidget {
  const Halftone({super.key, this.color = const Color(0x14000000)});
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _DotsPainter(color), size: Size.infinite)),
  );
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, BP.dots(color));

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

/// A strip of diagonal black and yellow hazard tape.
class HazardTape extends StatelessWidget {
  const HazardTape({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height, width: double.infinity, child: const CustomPaint(painter: _TapePainter()));
}

class _TapePainter extends CustomPainter {
  const _TapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = BP.hazard);
    final step = size.height * 2.2;
    final path = Path();
    for (var x = -size.height; x < size.width + size.height; x += step) {
      path
        ..moveTo(x, r.bottom)
        ..lineTo(x + step / 2, r.bottom)
        ..lineTo(x + step / 2 + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = BP.paper);
    // A hard black edge where the tape meets the paper.
    final edge = Paint()..color = BP.paper;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2), edge);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), edge);
  }

  @override
  bool shouldRepaint(_TapePainter old) => false;
}

/// The big red arcade button on the start screen, drawn the same way the
/// game draws its buttons: outline, skirt, a face that sinks, one shine.
/// With [attract] on, a ring ripples out of the bezel now and then to say
/// "press me" (never with reduce motion).
class VoidButton extends StatefulWidget {
  const VoidButton({super.key, required this.size, required this.onTap, this.semantic = 'Start', this.label = 'PRESS', this.attract = true});
  final double size;
  final VoidCallback onTap;
  final String semantic;
  final String label;
  final bool attract;

  @override
  State<VoidButton> createState() => _VoidButtonState();
}

class _VoidButtonState extends State<VoidButton> with SingleTickerProviderStateMixin {
  bool _down = false;
  bool _hot = false;
  late final AnimationController _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.attract && !still) {
      if (!_ripple.isAnimating) _ripple.repeat();
    } else {
      _ripple.stop();
      _ripple.value = 0;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      button: true,
      label: widget.semantic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hot = true),
        onExit: (_) => setState(() => _hot = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: SizedBox(
            width: size * 1.3,
            height: size * 1.3,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ripple,
                builder: (context, _) => CustomPaint(
                  painter: _ArcadePainter(down: _down, hot: _hot, label: widget.label, ripple: _ripple.isAnimating ? _ripple.value : -1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcadePainter extends CustomPainter {
  _ArcadePainter({required this.down, required this.label, this.hot = false, this.ripple = -1});
  final bool down;
  final bool hot;
  final String label;

  /// 0..1 through the attract ripple, or negative for none.
  final double ripple;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 1.3 / 2;
    final ow = BP.outline(r);
    final fill = Paint();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ow
      ..color = BP.paper;
    // Attract ripple: a black ring leaving the bezel in the first half of
    // each cycle, then rest.
    if (ripple >= 0 && ripple < 0.55 && !down) {
      final t = ripple / 0.55;
      canvas.drawCircle(
        c,
        r * (1.26 + 0.3 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ow * (1 - t * 0.6)
          ..color = BP.paper.withValues(alpha: 0.55 * (1 - t)),
      );
    }
    // Bezel: hazard ring with a black rim and a hard shadow.
    canvas.drawCircle(c.translate(r * 0.06, r * 0.1), r * 1.22, fill..color = BP.paper);
    canvas.drawCircle(c, r * 1.22, fill..color = BP.hazard);
    canvas.drawCircle(c, r * 1.22, stroke);
    // Bolts on the bezel, like a panel-mounted switch.
    for (var k = 0; k < 4; k++) {
      final a = math.pi / 4 + k * math.pi / 2;
      final bolt = c + Offset(math.cos(a), math.sin(a)) * r * 1.11;
      canvas.drawCircle(bolt, r * 0.045, fill..color = BP.paper);
    }
    final depth = r * 0.2;
    final sink = down ? depth : (hot ? depth * 0.25 : 0.0);
    final skirt = c.translate(0, depth * 0.5);
    final top = c.translate(0, -depth * 0.5 + sink);
    final side = BP.shade(BP.signal, 0.42);
    canvas.drawCircle(skirt, r, fill..color = side);
    canvas.drawCircle(skirt, r, stroke);
    canvas.drawRect(Rect.fromLTRB(c.dx - r, top.dy, c.dx + r, skirt.dy), fill..color = side);
    canvas.drawLine(Offset(c.dx - r, top.dy), Offset(c.dx - r, skirt.dy), stroke);
    canvas.drawLine(Offset(c.dx + r, top.dy), Offset(c.dx + r, skirt.dy), stroke);
    canvas.drawCircle(top, r, fill..color = BP.signal);
    canvas.drawCircle(top, r, stroke);
    canvas.drawOval(Rect.fromCenter(center: top.translate(-r * 0.36, -r * 0.44), width: r * 0.5, height: r * 0.24), fill..color = const Color(0x66FFFFFF));
    final tp = TextPainter(
      text: TextSpan(text: label, style: BP.d(r * 0.46, color: const Color(0xFFFFFFFF), spacing: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, top - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ArcadePainter old) => old.down != down || old.hot != hot || old.label != label || old.ripple != ripple;
}
