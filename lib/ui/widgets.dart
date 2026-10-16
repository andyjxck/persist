import 'package:flutter/widgets.dart';

import 'theme.dart';

/// The only control outside the game: a word you can press. No box, no
/// fill; it brightens on hover or focus and dims while held.
class StarkAction extends StatefulWidget {
  const StarkAction({super.key, required this.label, required this.onTap, this.size = 12, this.color = BP.muted, this.semantic});

  final String label;
  final VoidCallback? onTap;
  final double size;
  final Color color;
  final String? semantic;

  @override
  State<StarkAction> createState() => _StarkActionState();
}

class _StarkActionState extends State<StarkAction> {
  bool _hot = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final colour = !enabled ? BP.faint : (_down ? BP.faint : (_hot ? BP.paper : widget.color));
    return Semantics(
      button: true,
      label: widget.semantic ?? widget.label,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Text(widget.label, style: BP.label(widget.size, color: colour)),
          ),
        ),
      ),
    );
  }
}

/// The button on the start screen: the same flat disc the game draws.
class VoidButton extends StatefulWidget {
  const VoidButton({super.key, required this.size, required this.onTap, this.semantic = 'Start'});
  final double size;
  final VoidCallback onTap;
  final String semantic;

  @override
  State<VoidButton> createState() => _VoidButtonState();
}

class _VoidButtonState extends State<VoidButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size * (_down ? 0.95 : 1);
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
            width: widget.size,
            height: widget.size,
            child: Center(
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _down ? BP.shade(BP.signal, 0.28) : BP.signal),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
