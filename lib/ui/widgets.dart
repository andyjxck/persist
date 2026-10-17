import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// How a [StarkAction] looks.
enum ActionLook {
  /// A small square-edged switch (settings toggles, the phone's sound switch).
  chip,

  /// The main action: alarm-red slab, white type.
  primary,

  /// Other actions: dark slab with a hairline frame, pale type.
  secondary,

  /// A warning action: amber slab, black type.
  hazard,
}

/// A flat, machined slab button. It brightens under the mouse, sinks a
/// pixel when pressed, and shows a separate amber focus ring when reached
/// with the keyboard.
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

  /// Label colour for [ActionLook.chip].
  final Color color;
  final String? semantic;
  final ActionLook look;

  /// Shown as a small key inside the button (desktop shortcuts).
  final String? keyHint;

  /// For on/off switches: shows a lamp, lit when on.
  final bool? lit;

  @override
  State<StarkAction> createState() => _StarkActionState();
}

class _StarkActionState extends State<StarkAction> {
  bool _hot = false;
  bool _focus = false;
  bool _down = false;

  Widget _focusRing(double radius) => Positioned(
    left: -4,
    top: -4,
    right: -4,
    bottom: -4,
    child: IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: BP.hazard, width: 2),
          borderRadius: BorderRadius.circular(radius + 3),
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
                color: _down ? BP.ink : BP.inkSoft,
                border: Border.all(color: _hot ? BP.paper.withValues(alpha: 0.6) : BP.line, width: 1),
                borderRadius: BorderRadius.circular(BP.radius),
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
                        boxShadow: lit ? [BoxShadow(color: BP.hazard.withValues(alpha: 0.6), blurRadius: 6)] : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(widget.label, style: BP.label(widget.size, color: _hot ? BP.paper : widget.color)),
                ],
              ),
            ),
            if (_focus) _focusRing(BP.radius),
          ],
        ),
      );
    } else {
      final (Color face, Color hotFace, Color ink, Color? frame) = switch (look) {
        ActionLook.primary => (BP.signal, BP.tint(BP.signal, 0.12), const Color(0xFFFFFFFF), null),
        ActionLook.hazard => (BP.hazard, BP.tint(BP.hazard, 0.2), BP.ink, null),
        _ => (BP.inkSoft, BP.shade(BP.paper, 0.78), BP.paper, BP.paper.withValues(alpha: _hot ? 0.75 : 0.32)),
      };
      final hint = widget.keyHint;
      body = Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(0, _down ? 1.5 : 0),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: widget.size * 1.4, vertical: widget.size * 0.7),
                decoration: BoxDecoration(
                  color: _down ? BP.shade(face, 0.2) : (_hot ? hotFace : face),
                  border: frame == null ? null : Border.all(color: frame, width: 1.5),
                  borderRadius: BorderRadius.circular(BP.radius),
                  boxShadow: look == ActionLook.primary && !_down
                      ? [BoxShadow(color: BP.signal.withValues(alpha: _hot ? 0.45 : 0.25), blurRadius: _hot ? 18 : 12)]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.label, style: BP.d(widget.size * 1.6, color: ink, spacing: 1.5)),
                    if (hint != null) ...[
                      SizedBox(width: widget.size * 0.7),
                      KeyCap(hint, size: (widget.size * 0.62).clamp(8.0, 11.0), dark: look != ActionLook.secondary),
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

  /// A dark key with pale type (for bright slabs); otherwise a pale outline
  /// key for dark surfaces.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(size * 0.6, size * 0.28, size * 0.6, size * 0.22),
      decoration: BoxDecoration(
        color: dark ? const Color(0x55000000) : BP.ink,
        border: Border.all(color: dark ? const Color(0x66000000) : BP.paper.withValues(alpha: 0.35), width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(label, style: BP.label(size, color: dark ? const Color(0xFFFFFFFF) : BP.paper)),
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
            KeyCap(key, size: 10),
            const SizedBox(width: 7),
            Text(what, style: BP.label(11, color: color)),
          ],
        ),
    ],
  );
}

/// A stamped notice: a square frame in one colour, for marks such as NEW
/// BEST. Straight, not tilted, unless asked.
class Sticker extends StatelessWidget {
  const Sticker({super.key, required this.label, this.size = 22, this.color = BP.hazard, this.ink = BP.ink, this.angle = 0});
  final String label;
  final double size;
  final Color color;
  final Color ink;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.45, vertical: size * 0.16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      child: Text(label, style: BP.d(size, color: ink, spacing: 1.5)),
    ),
  );
}

/// Faint scanlines over a whole area, like an old monitor. One shader fill.
class Halftone extends StatelessWidget {
  const Halftone({super.key, this.color = const Color(0x0DFFFFFF)});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _LinesPainter(color), size: Size.infinite)));
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, BP.scanlines(color));

  @override
  bool shouldRepaint(_LinesPainter old) => old.color != color;
}

/// A warning strip: a thin alarm-red rule with short dashes under it.
class HazardTape extends StatelessWidget {
  const HazardTape({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height, child: CustomPaint(painter: _TapePainter(), size: Size.infinite));
}

class _TapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BP.ink);
    final rule = math.max(1.0, size.height * 0.25);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rule), Paint()..color = BP.signal);
    final dash = Paint()..color = BP.signal.withValues(alpha: 0.35);
    final y = rule + (size.height - rule) * 0.35;
    final h = math.max(1.0, (size.height - rule) * 0.4);
    for (var x = 0.0; x < size.width; x += 14) {
      canvas.drawRect(Rect.fromLTWH(x, y, 7, h), dash);
    }
  }

  @override
  bool shouldRepaint(_TapePainter old) => false;
}

/// A small lamp that blinks like a recording light. Holds still with
/// reduce motion.
class StatusLamp extends StatefulWidget {
  const StatusLamp({super.key, this.size = 8, this.color = BP.signal});
  final double size;
  final Color color;

  @override
  State<StatusLamp> createState() => _StatusLampState();
}

class _StatusLampState extends State<StatusLamp> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _blink.stop();
      _blink.value = 0;
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _blink,
    builder: (context, _) {
      final on = _blink.value < 0.55;
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? widget.color : BP.shade(widget.color, 0.7),
          boxShadow: on ? [BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: widget.size)] : null,
        ),
      );
    },
  );
}

/// The big button on the start screen: a matte red emergency button in a
/// dark steel collar, with a slow heartbeat glow that invites a press. The
/// heartbeat stops entirely with reduce motion.
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
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.attract && !still) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
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
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _PanicButtonPainter(down: _down, hot: _hot, label: widget.label, beat: _pulse.isAnimating ? heartbeat(_pulse.value) : 0),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A heartbeat envelope over one beat (0..1): a strong thump, a smaller
/// one just after, then quiet. Returns 0..1.
double heartbeat(double t) {
  double bump(double centre, double width) {
    final d = (t - centre) / width;
    return d.abs() >= 1 ? 0 : (1 - d * d) * (1 - d * d);
  }

  return math.max(bump(0.08, 0.08), bump(0.28, 0.09) * 0.6).clamp(0.0, 1.0);
}

class _PanicButtonPainter extends CustomPainter {
  _PanicButtonPainter({required this.down, required this.hot, required this.label, required this.beat});
  final bool down;
  final bool hot;
  final String label;

  /// Heartbeat glow, 0..1.
  final double beat;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 1.3 / 2;

    // The glow: a red halo that thumps with the heartbeat.
    final glow = 0.18 + beat * 0.5 + (hot ? 0.15 : 0);
    canvas.drawCircle(
      c,
      r * (1.12 + beat * 0.06),
      Paint()
        ..color = BP.signal.withValues(alpha: glow.clamp(0.0, 1.0) * 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );

    // Steel collar.
    canvas.drawCircle(c, r * 1.08, Paint()..color = const Color(0xFF1D2024));
    canvas.drawCircle(
      c,
      r * 1.08,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF3A3E44),
    );
    // Collar marks: twelve short ticks, like a dial.
    final tick = Paint()
      ..color = const Color(0xFF4A4F56)
      ..strokeWidth = math.max(1.0, r * 0.015);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 0.99), c + d * (r * 1.04), tick);
    }
    // Recess.
    canvas.drawCircle(c, r * 0.96, Paint()..color = BP.rim);

    // The button: matte red, darker towards its edge, pressed in when down.
    final face = down ? BP.shade(BP.signal, 0.25) : (hot ? BP.tint(BP.signal, 0.06) : BP.signal);
    final br = r * (down ? 0.86 : 0.9);
    canvas.drawCircle(
      c,
      br,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1,
          colors: [face, BP.shade(face, 0.45)],
        ).createShader(Rect.fromCircle(center: c, radius: br)),
    );
    // A thin rim catching the light.
    canvas.drawCircle(
      c,
      br,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.02)
        ..color = BP.tint(face, 0.25).withValues(alpha: 0.5),
    );

    final tp = TextPainter(
      text: TextSpan(text: label, style: BP.d(r * 0.34, color: const Color(0xFFFFFFFF), spacing: r * 0.03)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PanicButtonPainter old) => old.down != down || old.hot != hot || old.label != label || old.beat != beat;
}
