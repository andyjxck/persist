import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A chunky physical button for the UI (menus, game over, the web page):
/// raised on a darker base, lifts on hover, sinks when pressed.
class TactileButton extends StatefulWidget {
  const TactileButton({
    super.key,
    required this.label,
    required this.onTap,
    this.sub,
    this.color = BP.signal,
    this.textColor = BP.paper,
    this.height = 64,
    this.leading,
    this.trailing,
    this.compact = false,
  });

  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final Color color;
  final Color textColor;
  final double height;
  final Widget? leading;
  final String? trailing;
  final bool compact;

  @override
  State<TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<TactileButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final depth = widget.compact ? 4.0 : 6.0;
    final lift = _down ? depth * 0.15 : (_hover ? depth * 1.25 : depth);
    final base = widget.color;
    final ghost = base.a == 0;
    final face = ghost ? const Color(0x00000000) : (_hover ? BP.tint(base, 0.07) : base);
    final radius = BorderRadius.circular(widget.height * 0.32);
    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          height: widget.height + depth,
          child: Stack(
            children: [
              // Base / side wall.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: widget.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ghost ? BP.line : BP.shade(base, 0.45),
                    borderRadius: radius,
                    boxShadow: ghost ? null : [BoxShadow(color: const Color(0x66000000), blurRadius: _hover ? 22 : 14, offset: const Offset(0, 8))],
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: Duration(milliseconds: _down ? 40 : 140),
                curve: _down ? Curves.easeOut : Curves.easeOutBack,
                left: 0,
                right: 0,
                top: depth - lift,
                height: widget.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ghost ? BP.surface : null,
                    gradient: ghost
                        ? null
                        : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [BP.tint(face, 0.14), face]),
                    borderRadius: radius,
                    border: Border.all(color: ghost ? BP.line : const Color(0x26FFFFFF), width: 1),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: widget.compact ? 16 : 22),
                    child: Row(
                      children: [
                        if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 14)],
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: widget.leading == null && widget.trailing == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BP.d(widget.compact ? 14 : 17, color: widget.textColor, spacing: 0.8),
                              ),
                              if (widget.sub != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.sub!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: BP.t(12.5, color: widget.textColor.withValues(alpha: 0.78), weight: FontWeight.w600, height: 1.2),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (widget.trailing != null)
                          Text(widget.trailing!, style: BP.d(widget.compact ? 16 : 20, color: widget.textColor.withValues(alpha: 0.9))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A keyboard key chip, for shortcut hints on the web.
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
      decoration: BoxDecoration(
        color: BP.surfaceHi,
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          top: BorderSide(color: BP.line),
          left: BorderSide(color: BP.line),
          right: BorderSide(color: BP.line),
          bottom: BorderSide(color: BP.line, width: 3),
        ),
      ),
      child: Text(label, style: BP.t(12, weight: FontWeight.w800, height: 1.2)),
    );
  }
}

/// Small round icon button with hover state (sound toggle etc).
class IconPill extends StatefulWidget {
  const IconPill({super.key, required this.painter, required this.onTap, this.label, this.semantic = ''});
  final CustomPainter painter;
  final VoidCallback onTap;
  final String? label;
  final String semantic;

  @override
  State<IconPill> createState() => _IconPillState();
}

class _IconPillState extends State<IconPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semantic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: widget.label == null ? 0 : 14),
            constraints: const BoxConstraints(minWidth: 44),
            decoration: BoxDecoration(
              color: _hover ? BP.surfaceHi : BP.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _hover ? BP.faint : BP.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 20, height: 20, child: CustomPaint(painter: widget.painter)),
                if (widget.label != null) ...[
                  const SizedBox(width: 8),
                  Text(widget.label!, style: BP.t(13, weight: FontWeight.w700, color: BP.paper)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Speaker glyph, with waves or a slash.
class SpeakerPainter extends CustomPainter {
  SpeakerPainter(this.on, {this.color = BP.paper});
  final bool on;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 20;
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(2 * s, 7.5 * s)
        ..lineTo(5.5 * s, 7.5 * s)
        ..lineTo(10 * s, 3.5 * s)
        ..lineTo(10 * s, 16.5 * s)
        ..lineTo(5.5 * s, 12.5 * s)
        ..lineTo(2 * s, 12.5 * s)
        ..close(),
      fill,
    );
    if (on) {
      canvas.drawArc(Rect.fromCircle(center: Offset(10 * s, 10 * s), radius: 4 * s), -0.9, 1.8, false, line);
      canvas.drawArc(Rect.fromCircle(center: Offset(10 * s, 10 * s), radius: 7.5 * s), -0.9, 1.8, false, line);
    } else {
      canvas.drawLine(Offset(13 * s, 7 * s), Offset(19 * s, 13 * s), line);
      canvas.drawLine(Offset(19 * s, 7 * s), Offset(13 * s, 13 * s), line);
    }
  }

  @override
  bool shouldRepaint(SpeakerPainter old) => old.on != on || old.color != color;
}

/// Phone-vibrating glyph.
class VibratePainter extends CustomPainter {
  VibratePainter(this.on);
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 20;
    final line = Paint()
      ..color = BP.paper
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6.5 * s, 3 * s, 7 * s, 14 * s), Radius.circular(1.8 * s)), line);
    if (on) {
      canvas.drawLine(Offset(3 * s, 7 * s), Offset(3 * s, 13 * s), line);
      canvas.drawLine(Offset(17 * s, 7 * s), Offset(17 * s, 13 * s), line);
    } else {
      canvas.drawLine(Offset(3 * s, 3 * s), Offset(17 * s, 17 * s), line);
    }
  }

  @override
  bool shouldRepaint(VibratePainter old) => old.on != on;
}

/// The logo mark: a little arcade button seen from the front.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r * 0.92);
    canvas.drawCircle(c + Offset(0, r * 0.14), r * 0.98, Paint()..color = const Color(0xFF07060A));
    canvas.drawCircle(c + Offset(0, r * 0.12), r * 0.8, Paint()..color = BP.shade(BP.signal, 0.5));
    canvas.drawCircle(
      c,
      r * 0.8,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.0,
          colors: [BP.tint(BP.signal, 0.3), BP.signal, BP.shade(BP.signal, 0.25)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.8)),
    );
    canvas.drawOval(
      Rect.fromCenter(center: c - Offset(r * 0.15, r * 0.38), width: r * 0.8, height: r * 0.32),
      Paint()..color = const Color(0x40FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The wordmark: BUTTON / PANIC in Unbounded, with the O as the button.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 56, this.align = CrossAxisAlignment.center});
  final double size;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('BUTTON', style: BP.d(size, height: 0.95, spacing: -size * 0.02)),
        Text('PANIC', style: BP.d(size, height: 0.95, color: BP.signal, spacing: -size * 0.02)),
      ],
    );
  }
}

/// A little countdown-ring motif for headers and how-to cards.
class RingGlyph extends StatelessWidget {
  const RingGlyph({super.key, this.size = 44, this.fraction = 0.68, this.color = BP.paper, this.button = BP.signal});
  final double size;
  final double fraction;
  final Color color;
  final Color button;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _RingGlyphPainter(fraction, color, button)));
}

class _RingGlyphPainter extends CustomPainter {
  _RingGlyphPainter(this.f, this.color, this.button);
  final double f;
  final Color color;
  final Color button;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final stroke = r * 0.12;
    canvas.drawCircle(c, r - stroke, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.12));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r - stroke), -math.pi / 2, math.pi * 2 * f, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color);
    canvas.drawCircle(c, r * 0.55, Paint()..color = button);
    canvas.drawOval(Rect.fromCenter(center: c - Offset(r * 0.1, r * 0.25), width: r * 0.5, height: r * 0.2), Paint()..color = const Color(0x44FFFFFF));
  }

  @override
  bool shouldRepaint(_RingGlyphPainter old) => old.f != f || old.color != color;
}
