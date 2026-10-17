import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/logic/story.dart';
import 'package:button_panic/services/leaderboard.dart';
import 'package:button_panic/ui/game_over_overlay.dart';
import 'package:button_panic/ui/leaderboard_overlay.dart';
import 'package:button_panic/ui/menu_overlay.dart';
import 'package:button_panic/ui/story_overlay.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_leaderboard.dart';
import 'support/layout.dart';

// The new Story and leaderboard panels, and the screens around them, on the
// smallest phone (320x568): nothing overflows, and the buttons you need are
// on screen without hunting for them. A wide check runs alongside.

const _wide = Size(1280, 720);

RunResult _storyResult(int level, {required bool cleared, int? score, bool firstClear = false}) {
  final lv = storyLevel(level)!;
  return RunResult(
    mode: GameMode.story,
    score: score ?? (cleared ? lv.length : 2),
    reason: cleared ? lv.log : 'You pressed the one that said don\'t',
    best: lv.length,
    isNewBest: false,
    date: DateTime(2026, 10, 17),
    level: lv,
    cleared: cleared,
    firstClear: firstClear,
  );
}

void main() {
  setUpAll(loadFonts);

  group('Story panel', () {
    for (final cleared in [0, 4, 9, 10]) {
      for (final (size, wide) in [(phone, false), (_wide, true)]) {
        testWidgets('lays out at ${size.width.toInt()}x${size.height.toInt()} with $cleared shifts cleared', (tester) async {
          final game = await makeGame(prefs: {'story_cleared': cleared, 'story_attempts_1': 3});
          game.wide = wide;
          await pumpAt(tester, size, StoryOverlay(game: game));
          expect(tester.takeException(), isNull);
          expect(find.text('PANEL 7'), findsOneWidget);
          expect(find.text('$cleared/10 SHIFTS CLEARED'), findsOneWidget);
          expectOnScreen(tester, const Key('closeStory'), size);
          // Cleared shifts and the next one can be played; locked ones can't.
          final open = (cleared + 1).clamp(1, 10);
          // The next shift has been scrolled into view (with every shift
          // cleared there is no next one, and the list starts at the top).
          expectOnScreen(tester, Key(cleared < 10 ? 'shift$open' : 'shift1'), size);
          if (cleared < 10) expect(find.text('NEXT'), findsOneWidget);
          expect(find.textContaining('SPACE'), wide ? findsWidgets : findsNothing);
          // Scroll the list from top to bottom: every shift card is laid out
          // without overflow, and only cleared shifts and the next one can be
          // tapped.
          final list = find.byType(Scrollable).first;
          await tester.drag(list, const Offset(0, 4000));
          await tester.pumpAndSettle();
          final seen = <int>{};
          for (var step = 0; step < 40 && seen.length < 10; step++) {
            for (final lv in storyLevels) {
              if (find.text(lv.title).evaluate().isEmpty) continue;
              seen.add(lv.number);
              expect(find.byKey(Key('shift${lv.number}')), lv.number <= open ? findsOneWidget : findsNothing, reason: 'shift ${lv.number}');
            }
            await tester.drag(list, const Offset(0, -120));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          expect(seen, hasLength(10));
        });
      }
    }
  });

  group('Leaderboard panel', () {
    for (final (size, wide) in [(phone, false), (_wide, true)]) {
      final at = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('lays out at $at with a full board and no name yet', (tester) async {
        final api = FakeLeaderboardApi();
        final game = await makeGame(boards: api);
        game.wide = wide;
        await pumpAt(tester, size, LeaderboardOverlay(game: game));
        expect(tester.takeException(), isNull);
        expect(api.topCalls, 1);
        expect(find.text('BOARDS'), findsOneWidget);
        expect(find.text('P1'), findsOneWidget);
        expect(find.byKey(const Key('myRow'), skipOffstage: false), findsOneWidget);
        expectOnScreen(tester, const Key('closeBoards'), size);
        expectOnScreen(tester, const Key('nameField'), size);
        expectOnScreen(tester, const Key('nameSubmit'), size);
      });

      testWidgets('lays out at $at with a long name saved, and switches boards', (tester) async {
        final api = FakeLeaderboardApi();
        final game = await makeGame(boards: api, prefs: {'lb_name': 'WWWWWWWWWWWWWW'});
        game.wide = wide;
        await pumpAt(tester, size, LeaderboardOverlay(game: game));
        expect(tester.takeException(), isNull);
        expectOnScreen(tester, const Key('renameButton'), size);
        expect(find.byKey(const Key('nameField')), findsNothing);
        game.boardTab.value = 1;
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(api.topCalls, 2, reason: 'the Endless board loads when its tab opens');
        await tester.tap(find.byKey(const Key('renameButton')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectOnScreen(tester, const Key('nameField'), size);
      });

      testWidgets('says so at $at when nobody has played or the board can\'t load', (tester) async {
        final game = await makeGame(boards: FakeLeaderboardApi(rows: const []));
        game.wide = wide;
        await pumpAt(tester, size, LeaderboardOverlay(game: game));
        expect(find.text('NOBODY HAS PLAYED TODAY YET.'), findsOneWidget);
        final broken = await makeGame(boards: FakeLeaderboardApi(topError: 'offline'));
        broken.wide = wide;
        await pumpAt(tester, size, LeaderboardOverlay(key: const Key('broken'), game: broken));
        expect(tester.takeException(), isNull);
        expect(find.text(const LeaderboardException('offline').message.toUpperCase()), findsOneWidget);
      });
    }
  });

  group('Story result screens', () {
    for (final (size, wide) in [(phone, false), (_wide, true)]) {
      final at = '${size.width.toInt()}x${size.height.toInt()}';
      for (final (level, cleared, first) in [(1, true, true), (3, false, false), (10, true, false), (10, false, false)]) {
        testWidgets('shift $level ${cleared ? 'cleared' : 'failed'} lays out at $at', (tester) async {
          final game = await makeGame(prefs: {'story_cleared': cleared ? level : level - 1, 'story_attempts_$level': 2});
          game.wide = wide;
          game.phase = GamePhase.gameOver;
          game.lastResult = _storyResult(level, cleared: cleared, firstClear: first);
          await pumpAt(tester, size, GameOverOverlay(game: game));
          expect(tester.takeException(), isNull);
          expectOnScreen(tester, const Key('againButton'), size);
          expectOnScreen(tester, const Key('shiftsButton'), size);
          if (first) expect(find.text('FIRST CLEAR'), findsOneWidget);
          if (!cleared) expect(find.text('SHIFT FAILED'), findsOneWidget);
          // Story never offers the leaderboards.
          expect(find.byType(BoardStatus), findsNothing);
        });
      }
    }
  });

  group('Result screen with the boards on', () {
    for (final (size, wide) in [(phone, false), (_wide, true)]) {
      final at = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('a first score asks for a name at $at without pushing AGAIN off screen', (tester) async {
        final api = FakeLeaderboardApi();
        final game = await makeGame(boards: api);
        game.wide = wide;
        game.leaderboards.runStarted('endless:phone');
        game.leaderboards.runEnded(148);
        expect(game.leaderboards.status, SubmitStatus.needsName);
        game.phase = GamePhase.gameOver;
        game.lastResult = RunResult(mode: GameMode.endless, score: 148, reason: 'Too slow', best: 148, isNewBest: true, date: DateTime(2026, 10, 17));
        await pumpAt(tester, size, GameOverOverlay(game: game));
        expect(tester.takeException(), isNull);
        expect(find.text('PUT THIS ON THE ENDLESS BOARD'), findsOneWidget);
        expectOnScreen(tester, const Key('againButton'), size);
        // The name box may sit below the fold on the smallest phone, but it
        // must be reachable and laid out without overflow.
        expect(find.byKey(const Key('nameField'), skipOffstage: false), findsOneWidget);
      });

      testWidgets('a sent score shows its rank at $at', (tester) async {
        final game = await makeGame(boards: FakeLeaderboardApi(rank: 12), prefs: {'lb_name': 'ANDREW'});
        game.wide = wide;
        game.leaderboards.runStarted('daily:phone:2026-10-17');
        game.leaderboards.runEnded(23);
        game.phase = GamePhase.gameOver;
        game.lastResult = RunResult(
          mode: GameMode.daily,
          score: 23,
          reason: 'Too slow',
          best: 23,
          isNewBest: false,
          date: DateTime(2026, 10, 17),
          dailyFirst: 23,
        );
        await pumpAt(tester, size, GameOverOverlay(game: game));
        expect(tester.takeException(), isNull);
        expect(find.text('#12 ON TODAY\u2019S BOARD'), findsOneWidget);
        expectOnScreen(tester, const Key('againButton'), size);
      });
    }

    testWidgets('practice runs and boards-off builds never show the board line', (tester) async {
      final game = await makeGame();
      game.phase = GamePhase.gameOver;
      game.lastResult = RunResult(mode: GameMode.endless, score: 9, reason: 'Too slow', best: 9, isNewBest: false, date: DateTime(2026, 10, 17));
      await pumpAt(tester, phone, GameOverOverlay(game: game));
      expect(find.byType(BoardStatus), findsNothing);
    });
  });

  group('Menu', () {
    testWidgets('on the smallest phone, Story is on screen and BOARDS only shows when the boards are on', (tester) async {
      final off = await makeGame();
      await pumpAt(tester, phone, MenuOverlay(game: off));
      expect(tester.takeException(), isNull);
      expectOnScreen(tester, const Key('storyButton'), phone);
      expect(find.byKey(const Key('boardsChip')), findsNothing);
      expect(find.byKey(const Key('boardsButton')), findsNothing);

      final on = await makeGame(boards: FakeLeaderboardApi());
      await pumpAt(tester, phone, MenuOverlay(key: const Key('on'), game: on));
      expect(tester.takeException(), isNull);
      expectOnScreen(tester, const Key('boardsChip'), phone);
      expectOnScreen(tester, const Key('storyButton'), phone);
      expectOnScreen(tester, const Key('dailyButton'), phone);
    });

    testWidgets('on desktop, BOARDS (L) only shows when the boards are on', (tester) async {
      final off = await makeGame();
      off.wide = true;
      await pumpAt(tester, _wide, MenuOverlay(game: off));
      expect(find.byKey(const Key('boardsButton')), findsNothing);
      final on = await makeGame(boards: FakeLeaderboardApi());
      on.wide = true;
      await pumpAt(tester, _wide, MenuOverlay(key: const Key('on'), game: on));
      expect(tester.takeException(), isNull);
      expectOnScreen(tester, const Key('boardsButton'), _wide);
      expectOnScreen(tester, const Key('storyButton'), _wide);
    });
  });
}
