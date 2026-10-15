import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import 'theme.dart';
import 'widgets.dart';

/// The game-over screen. The surprise TRY AGAIN shows this exact screen for
/// a moment first, so it must not look any different: the buttons just
/// don't respond while the game is in its fake phase.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> with SingleTickerProviderStateMixin {
  ButtonPanicGame get game => widget.game;
  bool get _live => game.phase == GamePhase.gameOver;
  bool _copied = false;

  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _share(RunResult result) async {
    final text = result.shareText;
    var shared = false;
    if (!kIsWeb) {
      try {
        final r = await SharePlus.instance.share(ShareParams(text: text));
        shared = r.status != ShareResultStatus.unavailable;
      } catch (_) {}
    }
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  Widget _rise(double from, double to, Widget child) {
    final anim = CurvedAnimation(parent: _in, curve: Interval(from, to, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: anim,
      builder: (context, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, (1 - anim.value) * 18), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = game.lastResult;
    if (result == null) return const SizedBox.shrink();
    final daily = result.mode == GameMode.daily;
    final wide = game.wide;
    final status = result.isNewBest
        ? 'NEW BEST'
        : result.practice
        ? 'PRACTICE · NOT SAVED'
        : daily
        ? 'DAILY · ${prettyDate(result.date).toUpperCase()} · BEST ${result.best}'
        : 'ENDLESS · BEST ${result.best}';

    final actions = [
      TactileButton(
        key: const Key('againButton'),
        label: 'PLAY AGAIN',
        trailing: wide ? null : '\u21bb',
        height: 64,
        onTap: () => _live ? game.startRun(result.mode) : null,
      ),
      TactileButton(
        key: const Key('shareButton'),
        label: _copied ? 'COPIED' : (kIsWeb ? 'COPY RESULT' : 'SHARE RESULT'),
        color: const Color(0x00000000),
        height: 56,
        onTap: () => _live ? _share(result) : null,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.1,
          colors: [const Color(0xF21A0C12), BP.ink.withValues(alpha: 0.97)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BP.s5),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 560 : 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rise(0, 0.5, Text('GAME OVER', textAlign: TextAlign.center, style: BP.label(13, color: BP.signal))),
                  const SizedBox(height: BP.s3),
                  _rise(
                    0.05,
                    0.55,
                    Text(result.reason, textAlign: TextAlign.center, style: BP.d(wide ? 26 : 22, weight: FontWeight.w600, height: 1.2)),
                  ),
                  const SizedBox(height: BP.s6),
                  _rise(
                    0.15,
                    0.75,
                    Text('${result.score}', textAlign: TextAlign.center, style: BP.d(wide ? 128 : 112, height: 0.9, spacing: -4)),
                  ),
                  const SizedBox(height: BP.s2),
                  _rise(
                    0.2,
                    0.8,
                    Text(result.score == 1 ? 'ROUND SURVIVED' : 'ROUNDS SURVIVED', textAlign: TextAlign.center, style: BP.label(12)),
                  ),
                  const SizedBox(height: BP.s4),
                  _rise(
                    0.25,
                    0.85,
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: result.isNewBest ? BP.amber.withValues(alpha: 0.14) : BP.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: result.isNewBest ? BP.amber : BP.line),
                        ),
                        child: Text(status, style: BP.label(10.5, color: result.isNewBest ? BP.amber : BP.muted)),
                      ),
                    ),
                  ),
                  SizedBox(height: wide ? BP.s7 : BP.s7 + BP.s4),
                  _rise(
                    0.35,
                    1,
                    wide
                        ? Row(
                            children: [
                              Expanded(child: actions[0]),
                              const SizedBox(width: BP.s3),
                              Expanded(child: actions[1]),
                            ],
                          )
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [actions[0], const SizedBox(height: BP.s3), actions[1]]),
                  ),
                  const SizedBox(height: BP.s4),
                  _rise(
                    0.4,
                    1,
                    Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _live ? game.backToMenu() : null,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Padding(
                            padding: const EdgeInsets.all(BP.s3),
                            child: Text(wide ? 'Back to menu  (Esc)' : 'Back to menu', style: BP.t(14, color: BP.muted, weight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
