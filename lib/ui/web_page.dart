import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import 'stage.dart';
import 'theme.dart';

/// The web version on a big screen: no page around it. The game fills the
/// window edge to edge, played with mouse and keyboard.
class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.game, required this.gameKey});
  final ButtonPanicGame game;
  final GlobalKey gameKey;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  ButtonPanicGame get game => widget.game;
  final _focus = FocusNode(debugLabel: 'page');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _toggleSound() => setState(() => game.setSound(!game.audio.enabled));

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final label = k == LogicalKeyboardKey.space ? 'Space' : k.keyLabel;
    switch (game.phase) {
      case GamePhase.playing:
      case GamePhase.roundWon:
      case GamePhase.failing:
      case GamePhase.fakeGameOver:
        // Every key is part of the game while playing (some rounds are traps).
        game.keyDown(label);
        return KeyEventResult.handled;
      case GamePhase.menu:
        if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
          game.startRun(GameMode.daily);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.keyE) {
          game.startRun(GameMode.endless);
          return KeyEventResult.handled;
        }
      case GamePhase.gameOver:
        if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.keyR) {
          game.startRun(game.lastResult?.mode ?? GameMode.endless);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.escape) {
          game.backToMenu();
          return KeyEventResult.handled;
        }
    }
    if (k == LogicalKeyboardKey.keyM) {
      _toggleSound();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: BP.ink,
        // Its own layer: the game repaints every frame, nothing else does.
        child: RepaintBoundary(child: GameStage(game: game, gameKey: widget.gameKey)),
      ),
    );
  }
}
