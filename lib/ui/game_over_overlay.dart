import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';

/// The game-over screen. The surprise TRY AGAIN shows this exact screen for
/// half a second first, so it must not look any different: the buttons just
/// don't respond while the game is in its fake phase.
class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  bool get _live => game.phase == GamePhase.gameOver;

  Future<void> _share(BuildContext context, RunResult result) async {
    final text = result.shareText;
    var shared = false;
    try {
      final r = await SharePlus.instance.share(ShareParams(text: text));
      shared = r.status != ShareResultStatus.unavailable;
    } catch (_) {}
    if (!shared || kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Result copied. Paste it anywhere.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = game.lastResult;
    if (result == null) return const SizedBox.shrink();
    final daily = result.mode == GameMode.daily;
    return Container(
      color: const Color(0xF2111117),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'GAME OVER',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 3, color: Color(0xFFFF5252)),
              ),
              const SizedBox(height: 10),
              Text(
                result.reason,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, color: Colors.white70, height: 1.3),
              ),
              const SizedBox(height: 28),
              Text(
                '${result.score}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w900, height: 1),
              ),
              Text(
                result.score == 1 ? 'ROUND SURVIVED' : 'ROUNDS SURVIVED',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, letterSpacing: 2, color: Colors.white60),
              ),
              const SizedBox(height: 14),
              Text(
                result.isNewBest
                    ? 'New best!'
                    : result.practice
                    ? 'Practice run \u00b7 not saved'
                    : daily
                    ? 'Daily \u00b7 ${prettyDate(result.date)} \u00b7 best today ${result.best}'
                    : 'Endless \u00b7 best ${result.best}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: result.isNewBest ? const Color(0xFFFFD740) : Colors.white54,
                  fontWeight: result.isNewBest ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('shareButton'),
                onPressed: () => _live ? _share(context, result) : null,
                icon: const Icon(Icons.ios_share),
                label: const Text('SHARE RESULT'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF43A047),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('againButton'),
                onPressed: () => _live ? game.startRun(result.mode) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
                child: const Text('PLAY AGAIN'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _live ? game.backToMenu() : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.white24),
                ),
                child: const Text('MENU', style: TextStyle(color: Colors.white70, letterSpacing: 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
