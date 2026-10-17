import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import 'theme.dart';
import 'widgets.dart';

/// The start screen: nothing but the button. Pressing it starts today's
/// Daily. Everything else is a few faint words at the edges.
class MenuOverlay extends StatefulWidget {
  const MenuOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<MenuOverlay> {
  ButtonPanicGame get game => widget.game;

  String _dailyLine() {
    final daily = game.store.dailyFor(game.clock(), variant: game.dailyVariant);
    return daily == null ? 'TODAY\'S DAILY RUN' : 'TODAY ${daily.firstScore}  \u00b7  BEST ${daily.bestScore}';
  }

  @override
  Widget build(BuildContext context) {
    final wide = game.wide;
    final best = game.store.bestEndless;
    return ColoredBox(
      color: BP.ink,
      child: Column(
        children: [
          const HazardTape(height: 18),
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = (box.biggest.shortestSide * (wide ? 0.2 : 0.3)).clamp(90.0, 170.0);
                  final title = (box.maxWidth * (wide ? 0.11 : 0.2)).clamp(56.0, 132.0);
                  return Stack(
                    children: [
                      Positioned(
                        top: BP.s2,
                        right: BP.s2,
                        child: Row(
                          children: [
                            if (!kIsWeb)
                              StarkAction(
                                look: ActionLook.chip,
                                label: game.haptics.enabled ? 'BUZZ ON' : 'BUZZ OFF',
                                size: 11,
                                color: BP.ink,
                                semantic: 'Vibration',
                                onTap: () => setState(() => game.setHaptics(!game.haptics.enabled)),
                              ),
                            StarkAction(
                              look: ActionLook.chip,
                              label: game.audio.enabled ? 'SOUND ON' : 'SOUND OFF',
                              size: 11,
                              color: BP.ink,
                              semantic: 'Sound',
                              onTap: () => setState(() => game.setSound(!game.audio.enabled)),
                            ),
                          ],
                        ),
                      ),
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: BP.s7),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.rotate(
                                angle: -0.05,
                                child: Column(
                                  children: [
                                    Text('BUTTON', style: BP.d(title, height: 0.9)),
                                    Stack(
                                      children: [
                                        Transform.translate(offset: Offset(title * 0.05, title * 0.05), child: Text('PANIC', style: BP.d(title, height: 0.9))),
                                        Text('PANIC', style: BP.d(title, color: BP.signal, height: 0.9)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: wide ? BP.s5 : BP.s6),
                              VoidButton(key: const Key('dailyButton'), size: size, semantic: 'Start the daily run', onTap: () => game.startRun(GameMode.daily)),
                              const SizedBox(height: BP.s4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                color: BP.paper,
                                child: Text(_dailyLine(), style: BP.label(13, color: BP.hazard)),
                              ),
                              const SizedBox(height: BP.s5),
                              StarkAction(
                                key: const Key('endlessButton'),
                                label: best > 0 ? 'ENDLESS  \u00b7  BEST $best' : 'ENDLESS MODE',
                                size: 13,
                                onTap: () => game.startRun(GameMode.endless),
                              ),
                              if (wide) ...[
                                const SizedBox(height: BP.s4),
                                Text('SPACE = DAILY    E = ENDLESS    M = MUTE', style: BP.label(11, color: BP.faint)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const HazardTape(height: 18),
        ],
      ),
    );
  }
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
  }

  @override
  bool shouldRepaint(_TapePainter old) => false;
}
