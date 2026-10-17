import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/logic/story.dart';
import 'package:button_panic/services/leaderboard.dart';
import 'package:button_panic/services/storage.dart';
import 'package:button_panic/ui/leaderboard_overlay.dart';
import 'package:button_panic/ui/story_overlay.dart';
import 'package:button_panic/ui/web_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_leaderboard.dart';
import 'support/layout.dart' show loadFonts;

// Story and leaderboard panels on the desktop web page, driven by real key
// presses (S, L, Esc, Space, R, arrows) and taps, with the leaderboards off
// (this build) and on (an in-memory server).

Future<ButtonPanicGame> pumpWeb(WidgetTester tester, {Map<String, Object> prefs = const {}, FakeLeaderboardApi? boards}) async {
  SharedPreferences.setMockInitialValues({'sound_on': false, 'haptics_on': false, ...prefs});
  final store = await ScoreStore.open();
  final game = ButtonPanicGame(
    store: store,
    clock: () => DateTime(2026, 10, 17, 15),
    leaderboards: boards == null ? null : Leaderboards(store: store, api: boards),
  );
  game.wide = true;
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: WebPage(game: game, gameKey: GlobalKey()),
    ),
  );
  // Let Flame really load (it reads assets off the test clock), so the menu,
  // Story, leaderboard and result overlays are on screen like in a browser.
  for (var i = 0; i < 60 && !game.isLoaded; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(game.isLoaded, isTrue, reason: 'the game should load');
  await settle(tester);
  return game;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settle(tester);
}

int? playingShift(ButtonPanicGame game) {
  final e = game.engine;
  return e is StoryRunEngine && game.phase == GamePhase.playing ? e.level.number : null;
}

/// Puts the game on the result screen of a Story shift.
Future<void> showStoryResult(WidgetTester tester, ButtonPanicGame game, int level, {required bool cleared}) async {
  final lv = storyLevel(level)!;
  if (cleared) await game.store.recordStoryClear(level);
  game.lastResult = RunResult(
    mode: GameMode.story,
    score: cleared ? lv.length : 1,
    reason: cleared ? lv.log : 'Too slow',
    best: lv.length,
    isNewBest: false,
    date: DateTime(2026, 10, 17),
    level: lv,
    cleared: cleared,
  );
  game.round = null;
  game.overlays.removeAll(['menu']);
  game.phase = GamePhase.gameOver;
  game.overlays.add('gameOver');
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  group('Story panel', () {
    testWidgets('S opens Story from the menu, Esc closes it, S toggles it', (tester) async {
      final game = await pumpWeb(tester);
      expect(find.byType(StoryOverlay), findsNothing);
      await press(tester, LogicalKeyboardKey.keyS);
      expect(game.panel, 'story');
      expect(find.byType(StoryOverlay), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(game.panel, isNull);
      expect(find.byType(StoryOverlay), findsNothing);
      expect(game.phase, GamePhase.menu, reason: 'Esc on a panel only closes the panel');
      await press(tester, LogicalKeyboardKey.keyS);
      await press(tester, LogicalKeyboardKey.keyS);
      expect(game.panel, isNull);
    });

    testWidgets('Space in Story plays the furthest shift unlocked, not the Daily', (tester) async {
      final game = await pumpWeb(tester, prefs: {'story_cleared': 3});
      await press(tester, LogicalKeyboardKey.keyS);
      await press(tester, LogicalKeyboardKey.space);
      expect(playingShift(game), 4);
      expect(game.panel, isNull);
      expect(find.byType(StoryOverlay), findsNothing);
      expect(game.overlays.isActive('menu'), isFalse);
      expect(game.store.storyAttempts(4), 1);
    });

    testWidgets('Enter in Story does the same as Space', (tester) async {
      final game = await pumpWeb(tester);
      await press(tester, LogicalKeyboardKey.keyS);
      await press(tester, LogicalKeyboardKey.enter);
      expect(playingShift(game), 1);
    });

    testWidgets('tapping a cleared shift replays it; locked shifts can\'t be started', (tester) async {
      final game = await pumpWeb(tester, prefs: {'story_cleared': 2});
      await tester.tap(find.byKey(const Key('storyButton')));
      await settle(tester);
      expect(game.panel, 'story');
      expect(find.byKey(const Key('shift4')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('shift1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('shift1')));
      await settle(tester);
      expect(playingShift(game), 1);
      // Even asked for directly, a locked shift starts the furthest open one.
      game.backToMenu();
      await settle(tester);
      game.startStory(7);
      await settle(tester);
      expect(playingShift(game), 3);
    });

    testWidgets('the menu\'s Space still starts the Daily and E Endless once Story is closed', (tester) async {
      final game = await pumpWeb(tester);
      await press(tester, LogicalKeyboardKey.keyS);
      await press(tester, LogicalKeyboardKey.escape);
      await press(tester, LogicalKeyboardKey.space);
      expect(game.engine?.mode, GameMode.daily);
    });
  });

  group('Story result screen', () {
    testWidgets('after a clear, R plays the next shift', (tester) async {
      final game = await pumpWeb(tester);
      await showStoryResult(tester, game, 2, cleared: true);
      await press(tester, LogicalKeyboardKey.keyR);
      expect(playingShift(game), 3);
    });

    testWidgets('after a fail, Space plays the same shift again', (tester) async {
      final game = await pumpWeb(tester, prefs: {'story_cleared': 4});
      await showStoryResult(tester, game, 5, cleared: false);
      await press(tester, LogicalKeyboardKey.space);
      expect(playingShift(game), 5);
    });

    testWidgets('after clearing the last shift, again replays it', (tester) async {
      final game = await pumpWeb(tester, prefs: {'story_cleared': 9});
      await showStoryResult(tester, game, 10, cleared: true);
      await press(tester, LogicalKeyboardKey.keyR);
      expect(playingShift(game), 10);
    });

    testWidgets('S opens the shift list over the result, Esc closes only the list, then Esc goes to the menu', (tester) async {
      final game = await pumpWeb(tester);
      await showStoryResult(tester, game, 1, cleared: false);
      await press(tester, LogicalKeyboardKey.keyS);
      expect(game.panel, 'story');
      expect(game.phase, GamePhase.gameOver);
      await press(tester, LogicalKeyboardKey.escape);
      expect(game.panel, isNull);
      expect(game.phase, GamePhase.gameOver);
      await press(tester, LogicalKeyboardKey.escape);
      expect(game.phase, GamePhase.menu);
      expect(game.overlays.isActive('menu'), isTrue);
    });

    testWidgets('the SHIFTS button on the result screen opens the list', (tester) async {
      final game = await pumpWeb(tester);
      await showStoryResult(tester, game, 1, cleared: true);
      await tester.tap(find.byKey(const Key('shiftsButton')));
      await settle(tester);
      expect(game.panel, 'story');
      expect(find.byType(StoryOverlay), findsOneWidget);
    });
  });

  group('Leaderboards switched off (this build)', () {
    testWidgets('L does nothing, and the panel can\'t be forced open', (tester) async {
      final game = await pumpWeb(tester);
      expect(game.leaderboards.enabled, isFalse);
      expect(find.byKey(const Key('boardsButton')), findsNothing);
      await press(tester, LogicalKeyboardKey.keyL);
      expect(game.panel, isNull);
      expect(game.phase, GamePhase.menu);
      game.openPanel('leaderboard');
      await settle(tester);
      expect(find.byType(LeaderboardOverlay), findsNothing);
    });

    testWidgets('an Endless run never asks the server for anything', (tester) async {
      final game = await pumpWeb(tester);
      await press(tester, LogicalKeyboardKey.keyE);
      expect(game.engine?.mode, GameMode.endless);
      expect(game.leaderboards.status, SubmitStatus.none);
    });
  });

  group('Leaderboards switched on', () {
    testWidgets('L opens the boards, the arrows switch board, L or Esc closes', (tester) async {
      final api = FakeLeaderboardApi();
      final game = await pumpWeb(tester, boards: api, prefs: {'lb_name': 'ANDREW'});
      expect(find.byKey(const Key('boardsButton')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyL);
      expect(game.panel, 'leaderboard');
      expect(find.byType(LeaderboardOverlay), findsOneWidget);
      expect(game.boardTab.value, 0);
      expect(find.text('ANDREW'), findsWidgets);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(game.boardTab.value, 1);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(game.boardTab.value, 0);
      expect(api.topCalls, greaterThanOrEqualTo(2));
      await press(tester, LogicalKeyboardKey.keyL);
      expect(game.panel, isNull);
      await press(tester, LogicalKeyboardKey.keyL);
      await press(tester, LogicalKeyboardKey.escape);
      expect(game.panel, isNull);
      expect(game.phase, GamePhase.menu);
    });

    testWidgets('S swaps the boards for Story: only one panel is open at a time', (tester) async {
      final game = await pumpWeb(tester, boards: FakeLeaderboardApi(), prefs: {'lb_name': 'ANDREW'});
      await press(tester, LogicalKeyboardKey.keyL);
      game.openPanel('story');
      await settle(tester);
      expect(game.panel, 'story');
      expect(find.byType(LeaderboardOverlay), findsNothing);
      expect(find.byType(StoryOverlay), findsOneWidget);
    });

    testWidgets('typing a name: M, Space, S and L go into the box, not to the game', (tester) async {
      final game = await pumpWeb(tester, boards: FakeLeaderboardApi());
      await press(tester, LogicalKeyboardKey.keyL);
      expect(find.byKey(const Key('nameField')), findsOneWidget);
      await tester.showKeyboard(find.byKey(const Key('nameField')));
      await settle(tester);
      final soundBefore = game.audio.enabled;
      for (final k in [LogicalKeyboardKey.keyM, LogicalKeyboardKey.space, LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyL, LogicalKeyboardKey.arrowRight]) {
        await press(tester, k);
      }
      expect(game.audio.enabled, soundBefore, reason: 'M must not mute while typing');
      expect(game.phase, GamePhase.menu, reason: 'Space must not start a run while typing');
      expect(game.panel, 'leaderboard', reason: 'S and L must not swap or close the panel while typing');
      expect(game.boardTab.value, 0, reason: 'arrows move the text cursor while typing');
      await tester.enterText(find.byKey(const Key('nameField')), 'MUSS');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(game.leaderboards.name, 'MUSS');
      // Keyboard back on the page after saving: Esc closes the panel again.
      await press(tester, LogicalKeyboardKey.escape);
      expect(game.panel, isNull);
    });

    testWidgets('a Daily run asks the server for a run id when it starts', (tester) async {
      final api = FakeLeaderboardApi();
      final game = await pumpWeb(tester, boards: api);
      await press(tester, LogicalKeyboardKey.space);
      expect(game.engine?.mode, GameMode.daily);
      expect(api.started, ['daily:desktop:2026-10-17']);
    });

    testWidgets('a Story shift never goes on a board', (tester) async {
      final api = FakeLeaderboardApi();
      final game = await pumpWeb(tester, boards: api);
      await press(tester, LogicalKeyboardKey.keyS);
      await press(tester, LogicalKeyboardKey.space);
      expect(playingShift(game), 1);
      expect(api.started, isEmpty);
    });
  });
}
