import 'package:flutter/widgets.dart';

import 'theme.dart';

/// How a [StarkAction] looks.
enum ActionLook {
  /// A small black tag (settings toggles, the phone's sound switch).
  chip,

  /// The main action: red slab, white type, hard black shadow.
  primary,

  /// Other actions: paper slab, black type, hard black shadow.
  secondary,
}

/// A chunky sticker button with a thick outline and a hard offset shadow
/// that it presses down into.
class StarkAction extends StatefulWidget {
  const StarkAction({
    super.key,
    required this.label,
    required this.onTap,
    this.size = 12,
    this.color = BP.muted,
    this.semantic,
    this.look = ActionLook.secondary,
  });

  final String label;
  final VoidCallback? onTap;
  final double size;

  /// Text colour for [ActionLook.chip].
  final Color color;
  final String? semantic;
  final ActionLook look;

  @override
  State<StarkAction> createState() => _StarkActionState();
}

class _StarkActionState extends State<StarkAction> {
  bool _hot = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final look = widget.look;
    final Widget body;
    if (look == ActionLook.chip) {
      body = Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: _down ? BP.muted : BP.paper, borderRadius: BorderRadius.circular(4)),
          child: Text(widget.label, style: BP.label(widget.size, color: _hot ? BP.hazard : widget.color)),
        ),
      );
    } else {
      final primary = look == ActionLook.primary;
      const depth = 5.0;
      final sink = _down ? depth : 0.0;
      body = Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6 + depth, 6 + depth),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              left: depth,
              top: depth,
              right: -depth,
              bottom: -depth,
              child: Container(decoration: BoxDecoration(color: BP.paper, borderRadius: BorderRadius.circular(8))),
            ),
            Transform.translate(
              offset: Offset(sink, sink),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: widget.size * 1.5, vertical: widget.size * 0.75),
                decoration: BoxDecoration(
                  color: primary ? (_hot ? BP.shade(BP.signal, 0.1) : BP.signal) : (_hot ? BP.hazard : const Color(0xFFFFFFFF)),
                  border: Border.all(color: BP.paper, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.label, style: BP.d(widget.size * 1.6, color: primary ? const Color(0xFFFFFFFF) : BP.paper, spacing: 1)),
              ),
            ),
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
          onShowFocusHighlight: (v) => setState(() => _hot = v),
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

/// The big red arcade button on the start screen, drawn the same way the
/// game draws its buttons: outline, skirt, a face that sinks, one shine.
class VoidButton extends StatefulWidget {
  const VoidButton({super.key, required this.size, required this.onTap, this.semantic = 'Start', this.label = 'PRESS'});
  final double size;
  final VoidCallback onTap;
  final String semantic;
  final String label;

  @override
  State<VoidButton> createState() => _VoidButtonState();
}

class _VoidButtonState extends State<VoidButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      button: true,
      label: widget.semantic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: SizedBox(
            width: size * 1.3,
            height: size * 1.3,
            child: CustomPaint(painter: _ArcadePainter(down: _down, label: widget.label)),
          ),
        ),
      ),
    );
  }
}

class _ArcadePainter extends CustomPainter {
  _ArcadePainter({required this.down, required this.label});
  final bool down;
  final String label;

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
    // Bezel: hazard ring with a black rim.
    canvas.drawCircle(c.translate(0, r * 0.08), r * 1.22, fill..color = BP.paper);
    canvas.drawCircle(c, r * 1.22, fill..color = BP.hazard);
    canvas.drawCircle(c, r * 1.22, stroke);
    final depth = r * 0.2;
    final sink = down ? depth : 0.0;
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
  bool shouldRepaint(_ArcadePainter old) => old.down != down || old.label != label;
}
