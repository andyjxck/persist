import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import 'theme.dart';
import 'widgets.dart';

/// The start screen. On phones it's a full-screen title with the actions in
/// thumb reach at the bottom; on the web it sits inside the stage on the page.
class MenuOverlay extends StatefulWidget {
  const MenuOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<MenuOverlay> with SingleTickerProviderStateMixin {
  ButtonPanicGame get game => widget.game;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _start(GameMode mode) => game.startRun(mode);

  @override
  Widget build(BuildContext context) => game.wide ? _stage(context) : _phone(context);

  String _dailySub() {
    final today = game.clock();
    final daily = game.store.dailyFor(today);
    return daily == null ? '${prettyDate(today)} · same rounds for everyone' : 'Today: ${daily.firstScore} · best ${daily.bestScore}';
  }

  String _endlessSub() {
    final best = game.store.bestEndless;
    return best > 0 ? 'Your best: $best rounds' : 'As long as you last';
  }

  Widget _animatedRing(double size) => AnimatedBuilder(
    animation: _spin,
    builder: (context, _) {
      final f = 1 - _spin.value;
      final c = f > 0.5 ? BP.paper : (f > 0.25 ? BP.amber : BP.signal);
      return RingGlyph(size: size, fraction: f, color: c);
    },
  );

  // --- Phone -----------------------------------------------------------------

  Widget _phone(BuildContext context) {
    return ColoredBox(
      color: BP.ink,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(BP.s5, BP.s3, BP.s5, BP.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('v1.0', style: BP.label(10, color: BP.faint)),
                      const Spacer(),
                      IconPill(
                        semantic: 'Vibration',
                        painter: VibratePainter(game.haptics.enabled),
                        onTap: () => setState(() => game.setHaptics(!game.haptics.enabled)),
                      ),
                      const SizedBox(width: BP.s2),
                      IconPill(
                        semantic: 'Sound',
                        painter: SpeakerPainter(game.audio.enabled),
                        onTap: () => setState(() => game.setSound(!game.audio.enabled)),
                      ),
                    ],
                  ),
                  const Spacer(flex: 3),
                  Center(child: _animatedRing(112)),
                  const SizedBox(height: BP.s6),
                  const Wordmark(size: 54),
                  const SizedBox(height: BP.s4),
                  Text(
                    'Do what it says. One wrong move and it\'s over.\nIt gets faster. And stranger.',
                    textAlign: TextAlign.center,
                    style: BP.t(15.5, color: BP.muted),
                  ),
                  const Spacer(flex: 4),
                  TactileButton(
                    key: const Key('dailyButton'),
                    label: 'DAILY RUN',
                    sub: _dailySub(),
                    trailing: '\u2192',
                    height: 72,
                    onTap: () => _start(GameMode.daily),
                  ),
                  const SizedBox(height: BP.s3),
                  TactileButton(
                    key: const Key('endlessButton'),
                    label: 'ENDLESS',
                    sub: _endlessSub(),
                    trailing: '\u2192',
                    color: const Color(0x00000000),
                    height: 64,
                    onTap: () => _start(GameMode.endless),
                  ),
                  const SizedBox(height: BP.s4),
                  Text(
                    'Sound on. Thumbs ready.',
                    textAlign: TextAlign.center,
                    style: BP.label(10, color: BP.faint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Web stage -------------------------------------------------------------

  Widget _stage(BuildContext context) {
    return Container(
      color: BP.ink.withValues(alpha: 0.9),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(BP.s6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _animatedRing(96),
            const SizedBox(height: BP.s5),
            Text('READY WHEN YOU ARE', style: BP.label(12, color: BP.signal)),
            const SizedBox(height: BP.s3),
            Text('Do what it says.', textAlign: TextAlign.center, style: BP.d(44, spacing: -0.5)),
            const SizedBox(height: BP.s3),
            Text(
              'Read the instruction, beat the ring around the button. Every round is different.',
              textAlign: TextAlign.center,
              style: BP.t(16, color: BP.muted),
            ),
            const SizedBox(height: BP.s6),
            Row(
              children: [
                Expanded(
                  child: TactileButton(
                    key: const Key('dailyButton'),
                    label: 'DAILY RUN',
                    sub: _dailySub(),
                    height: 70,
                    onTap: () => _start(GameMode.daily),
                  ),
                ),
                const SizedBox(width: BP.s4),
                Expanded(
                  child: TactileButton(
                    key: const Key('endlessButton'),
                    label: 'ENDLESS',
                    sub: _endlessSub(),
                    color: const Color(0x00000000),
                    height: 70,
                    onTap: () => _start(GameMode.endless),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BP.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Kbd('Space'),
                const SizedBox(width: 8),
                Text('Daily', style: BP.t(13, color: BP.muted)),
                const SizedBox(width: 20),
                const Kbd('E'),
                const SizedBox(width: 8),
                Text('Endless', style: BP.t(13, color: BP.muted)),
                const SizedBox(width: 20),
                const Kbd('M'),
                const SizedBox(width: 8),
                Text('Mute', style: BP.t(13, color: BP.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
