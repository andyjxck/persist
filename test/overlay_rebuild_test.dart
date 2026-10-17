import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/main.dart';
import 'package:button_panic/services/storage.dart';
import 'package:button_panic/ui/game_over_overlay.dart';
import 'package:button_panic/ui/menu_overlay.dart';
import 'package:button_panic/ui/web_page.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/layout.dart' show loadFonts;

// Regression: Flame 1.38.2's GameWidget re-adds its initialActiveOverlays
// every time it is rebuilt. Pressing M (mute) or resizing the window
// mid-round rebuilt the stage, put the menu over the round, and the round
// was lost when its timer ran out. The screens over the canvas must come
// from the game's phase, whatever rebuilds.

Future<void> waitForLoad(WidgetTester tester, ButtonPanicGame game) async {
  for (var i = 0; i < 60 && !game.isLoaded; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(game.isLoaded, isTrue, reason: 'the game should load');
}

Future<void> frames(WidgetTester tester, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void expectRoundStillOn(ButtonPanicGame game, Object? round) {
  expect(game.phase, GamePhase.playing, reason: 'the round keeps going');
  expect(identical(game.round, round), isTrue, reason: 'same round, not restarted or lost');
  expect(game.overlays.isActive('menu'), isFalse, reason: 'no menu over the round');
  expect(game.overlays.isActive('gameOver'), isFalse);
  expect(find.byType(MenuOverlay), findsNothing);
  expect(find.byType(GameOverOverlay), findsNothing);
}

void main() {
  setUpAll(loadFonts);

  group('desktop web page', () {
    Future<ButtonPanicGame> pumpWeb(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'sound_on': false, 'haptics_on': false});
      final game = ButtonPanicGame(store: await ScoreStore.open(), clock: () => DateTime(2026, 10, 17, 15));
      game.wide = true;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      // Rebuilt on every size change, like the app's own LayoutBuilder.
      await tester.pumpWidget(
        MaterialApp(
          home: LayoutBuilder(
            builder: (context, box) => WebPage(game: game, gameKey: key),
          ),
        ),
      );
      await waitForLoad(tester, game);
      await frames(tester);
      return game;
    }

    testWidgets('M mid-round mutes and the round carries on with no menu', (tester) async {
      final game = await pumpWeb(tester);
      expect(find.byType(MenuOverlay), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await frames(tester, 2);
      final round = game.round;
      expect(round, isNotNull);
      expectRoundStillOn(game, round);

      final soundBefore = game.audio.enabled;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await frames(tester);
      expect(game.audio.enabled, !soundBefore, reason: 'M still toggles the sound');
      expectRoundStillOn(game, round);

      // And back again.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await frames(tester);
      expect(game.audio.enabled, soundBefore);
      expectRoundStillOn(game, round);
    });

    testWidgets('resizing mid-round keeps the round going with no menu', (tester) async {
      final game = await pumpWeb(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await frames(tester, 2);
      final round = game.round;
      tester.view.physicalSize = const Size(1200, 760);
      await frames(tester);
      expectRoundStillOn(game, round);
      tester.view.physicalSize = const Size(1500, 950);
      await frames(tester);
      expectRoundStillOn(game, round);
    });

    testWidgets('a rebuild on the result screen shows only the result, not the menu too', (tester) async {
      final game = await pumpWeb(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await frames(tester, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await frames(tester);
      // Lose the run: let the clock run out with no input.
      for (var i = 0; i < 400 && game.phase != GamePhase.gameOver; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (game.phase == GamePhase.fakeGameOver) {
        // A surprise TRY AGAIN can come first; play on until the real end.
        for (var i = 0; i < 600 && game.phase != GamePhase.gameOver; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      expect(game.phase, GamePhase.gameOver);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await frames(tester);
      expect(game.overlays.activeOverlays, ['gameOver']);
      expect(find.byType(GameOverOverlay), findsOneWidget);
      expect(find.byType(MenuOverlay), findsNothing);
      // Esc still goes back to the menu, and only the menu is up.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);
      expect(game.phase, GamePhase.menu);
      expect(game.overlays.activeOverlays, ['menu']);
    });

    testWidgets('panels still open over the menu and close again', (tester) async {
      final game = await pumpWeb(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await frames(tester);
      expect(game.overlays.activeOverlays, ['menu', 'story']);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await frames(tester);
      expect(game.overlays.activeOverlays, ['menu', 'story'], reason: 'a rebuild changes nothing');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);
      expect(game.overlays.activeOverlays, ['menu']);
    });
  });

  testWidgets('the whole app: a resize mid-round rebuilds the layout but keeps the round', (tester) async {
    SharedPreferences.setMockInitialValues({'sound_on': false, 'haptics_on': false});
    final store = await ScoreStore.open();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ButtonPanicApp(store: store));
    final game = tester.widget<GameWidget<ButtonPanicGame>>(find.byType(GameWidget<ButtonPanicGame>)).game!;
    await waitForLoad(tester, game);
    await frames(tester);
    expect(find.byType(MenuOverlay), findsOneWidget);

    game.startRun(GameMode.endless);
    await frames(tester, 2);
    final round = game.round;
    expectRoundStillOn(game, round);

    tester.view.physicalSize = const Size(320, 568);
    await frames(tester);
    expectRoundStillOn(game, round);

    // The phone's sound chip rebuilds the shell too.
    game.setSound(!game.audio.enabled);
    tester.view.physicalSize = const Size(414, 896);
    await frames(tester);
    expectRoundStillOn(game, round);
  });
}
