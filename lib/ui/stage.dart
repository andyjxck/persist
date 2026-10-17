import 'package:flame/game.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import 'game_over_overlay.dart';
import 'leaderboard_overlay.dart';
import 'menu_overlay.dart';
import 'story_overlay.dart';

/// The game canvas with raw input wired up: pointers (no gesture delays, so
/// holds, flicks and multi-touch are reliable), mouse hover and the cursor.
/// Used by both the phone screen and the web page's stage.
class GameStage extends StatelessWidget {
  const GameStage({super.key, required this.game, required this.gameKey});
  final ButtonPanicGame game;

  /// Keeps the same GameWidget alive if the window crosses between layouts.
  final GlobalKey gameKey;

  @override
  Widget build(BuildContext context) {
    // Flame's GameWidget registers its overlays (and, if given, re-adds any
    // initialActiveOverlays) in its constructor, i.e. on every rebuild of
    // this stage. So no initial overlays here: which screens are up always
    // comes from the game's phase, re-derived after the widget is made.
    final gameWidget = GameWidget<ButtonPanicGame>(
      key: gameKey,
      game: game,
      // Flame's own focus node swallows every key when it has focus and
      // the game has no KeyboardEvents. Keys are handled by the web
      // page's Focus around the stage, so the game must never take it.
      autofocus: false,
      overlayBuilderMap: {
        'menu': (context, game) => MenuOverlay(game: game),
        'gameOver': (context, game) => GameOverOverlay(game: game),
        // Side panels over the menu or the result screen. Only one is
        // open at a time (game.panel); the leaderboard is never
        // opened when the build has no leaderboard project.
        'story': (context, game) => StoryOverlay(game: game),
        'leaderboard': (context, game) =>
            game.leaderboards.enabled ? LeaderboardOverlay(game: game) : const SizedBox.shrink(),
      },
    );
    game.syncOverlays();
    return ValueListenableBuilder<bool>(
      valueListenable: game.overButton,
      builder: (context, over, child) => MouseRegion(
        cursor: over ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onHover: (e) => game.hover(e.localPosition),
        onExit: (_) => game.hover(null),
        child: child,
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => game.pointerDown(e.pointer, e.localPosition),
        onPointerMove: (e) {
          game.pointerMove(e.pointer, e.localPosition);
          if (e.kind == PointerDeviceKind.mouse) game.hover(e.localPosition);
        },
        onPointerUp: (e) => game.pointerUp(e.pointer),
        onPointerCancel: (e) => game.pointerUp(e.pointer),
        child: gameWidget,
      ),
    );
  }
}
