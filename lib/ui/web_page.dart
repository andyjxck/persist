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

  /// Keys that are only ever held with another key (Shift for a capital,
  /// Caps Lock, Ctrl, Alt, Cmd...). They never count as an answer.
  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.altGraph,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.superKey,
    LogicalKeyboardKey.hyper,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.fnLock,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.scrollLock,
  };

  /// Clicking the game puts the keyboard back on the page, in case anything
  /// (the browser, an overlay) took it.
  void _reclaimFocus() {
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // Shift, Caps Lock, Cmd and friends never count as a press. Ctrl/Cmd
    // shortcuts (refresh, zoom, new tab) are left to the browser.
    if (_modifiers.contains(k)) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) return KeyEventResult.ignored;
    // M mutes at any time, mid-round too. No round ever asks for M.
    if (k == LogicalKeyboardKey.keyM) {
      _toggleSound();
      return KeyEventResult.handled;
    }
    final label = k == LogicalKeyboardKey.space ? 'Space' : k.keyLabel;
    switch (game.phase) {
      case GamePhase.playing:
      case GamePhase.roundWon:
      case GamePhase.failing:
      case GamePhase.fakeGameOver:
        // Every other key is part of the game while playing (some rounds
        // are traps).
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
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _reclaimFocus(),
        child: ColoredBox(
          color: BP.ink,
          // Its own layer: the game repaints every frame, nothing else does.
          child: RepaintBoundary(child: GameStage(game: game, gameKey: widget.gameKey)),
        ),
      ),
    );
  }
}
