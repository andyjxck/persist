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
    final daily = game.store.dailyFor(game.clock());
    return daily == null ? 'PRESS IT' : 'TODAY  ${daily.firstScore}   BEST  ${daily.bestScore}';
  }

  @override
  Widget build(BuildContext context) {
    final wide = game.wide;
    final best = game.store.bestEndless;
    return ColoredBox(
      color: BP.ink,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final size = (box.biggest.shortestSide * (wide ? 0.26 : 0.42)).clamp(120.0, 220.0);
            return Stack(
              children: [
                Positioned(
                  top: BP.s4,
                  left: BP.s5,
                  child: Text('BUTTON PANIC', style: BP.label(10, color: BP.faint)),
                ),
                Positioned(
                  top: 0,
                  right: BP.s3,
                  child: Row(
                    children: [
                      if (!kIsWeb)
                        StarkAction(
                          label: game.haptics.enabled ? 'BUZZ' : 'NO BUZZ',
                          size: 10,
                          color: BP.faint,
                          semantic: 'Vibration',
                          onTap: () => setState(() => game.setHaptics(!game.haptics.enabled)),
                        ),
                      StarkAction(
                        label: game.audio.enabled ? 'SOUND' : 'MUTED',
                        size: 10,
                        color: BP.faint,
                        semantic: 'Sound',
                        onTap: () => setState(() => game.setSound(!game.audio.enabled)),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VoidButton(key: const Key('dailyButton'), size: size, semantic: 'Start the daily run', onTap: () => game.startRun(GameMode.daily)),
                      const SizedBox(height: BP.s6),
                      Text(_dailyLine(), style: BP.label(11, color: BP.muted)),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: BP.s3,
                  child: Column(
                    children: [
                      StarkAction(
                        key: const Key('endlessButton'),
                        label: best > 0 ? 'ENDLESS  ·  BEST $best' : 'ENDLESS',
                        size: 10,
                        color: BP.faint,
                        onTap: () => game.startRun(GameMode.endless),
                      ),
                      if (wide)
                        Text('SPACE  DAILY      E  ENDLESS      M  MUTE', style: BP.label(9, color: const Color(0xFF333332))),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
