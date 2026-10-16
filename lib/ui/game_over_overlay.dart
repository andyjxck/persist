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

  @override
  Widget build(BuildContext context) {
    final result = game.lastResult;
    if (result == null) return const SizedBox.shrink();
    final daily = result.mode == GameMode.daily;
    final wide = game.wide;
    final status = result.isNewBest
        ? 'NEW BEST'
        : result.practice
        ? 'PRACTICE  \u00b7  NOT SAVED'
        : daily
        ? 'DAILY  \u00b7  BEST ${result.best}'
        : 'ENDLESS  \u00b7  BEST ${result.best}';

    return FadeTransition(
      opacity: CurvedAnimation(parent: _in, curve: const Interval(0.3, 1)),
      child: ColoredBox(
        color: BP.ink,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BP.s5),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 560 : 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(result.reason.toUpperCase(), textAlign: TextAlign.center, style: BP.label(wide ? 12 : 11, color: BP.signal)),
                    const SizedBox(height: BP.s7),
                    Text('${result.score}', textAlign: TextAlign.center, style: BP.d(wide ? 132 : 112, weight: FontWeight.w500, height: 0.9, spacing: -4)),
                    const SizedBox(height: BP.s4),
                    Text(result.score == 1 ? 'ROUND' : 'ROUNDS', textAlign: TextAlign.center, style: BP.label(11, color: BP.faint)),
                    const SizedBox(height: BP.s3),
                    Text(status, textAlign: TextAlign.center, style: BP.label(10, color: result.isNewBest ? BP.paper : BP.faint)),
                    const SizedBox(height: BP.s8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: BP.s4,
                      children: [
                        StarkAction(
                          key: const Key('againButton'),
                          label: wide ? 'AGAIN  (SPACE)' : 'AGAIN',
                          size: 13,
                          color: BP.paper,
                          onTap: () => _live ? game.startRun(result.mode) : null,
                        ),
                        StarkAction(
                          key: const Key('shareButton'),
                          label: _copied ? 'COPIED' : (kIsWeb ? 'COPY' : 'SHARE'),
                          size: 13,
                          onTap: () => _live ? _share(result) : null,
                        ),
                        StarkAction(
                          label: wide ? 'MENU  (ESC)' : 'MENU',
                          size: 13,
                          onTap: () => _live ? game.backToMenu() : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
