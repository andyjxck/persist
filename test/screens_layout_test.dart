import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/services/storage.dart';
import 'package:button_panic/ui/game_over_overlay.dart';
import 'package:button_panic/ui/menu_overlay.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The start and game-over screens lay out cleanly (no overflow, nothing
// cut off) at every size the game is played at, with short and long
// scores, new bests and practice runs, with and without reduce motion.

const sizes = [
  (Size(320, 568), false),
  (Size(360, 640), false),
  (Size(390, 844), false),
  (Size(430, 932), false),
  (Size(820, 1180), false),
  (Size(1024, 640), true),
  (Size(1280, 720), true),
  (Size(1440, 900), true),
  (Size(1920, 1080), true),
];

Future<ButtonPanicGame> makeGame({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'sound_on': false, 'haptics_on': false, ...prefs});
  final store = await ScoreStore.open();
  return ButtonPanicGame(store: store, clock: () => DateTime(2026, 10, 17, 15));
}

Future<void> pumpAt(WidgetTester tester, Size size, Widget child, {bool still = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  // Real type, not the test font, so widths are what players see.
  await family('Anton', ['Anton-Regular.ttf']);
  await family('Manrope', ['Manrope-Medium.ttf', 'Manrope-SemiBold.ttf', 'Manrope-Bold.ttf', 'Manrope-ExtraBold.ttf']);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('menu attract ripple runs, and stops entirely with reduce motion', (tester) async {
    final game = await makeGame();
    game.wide = true;
    await pumpAt(tester, const Size(1280, 720), MenuOverlay(game: game));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await pumpAt(tester, const Size(1280, 720), MenuOverlay(key: const Key('still'), game: game), still: true);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('menu sound switch follows M (setSound) without a rebuild from outside', (tester) async {
    final game = await makeGame(prefs: {'sound_on': true});
    game.wide = true;
    await pumpAt(tester, const Size(1280, 720), MenuOverlay(game: game), still: true);
    expect(find.text('SOUND'), findsOneWidget);
    game.setSound(false);
    await tester.pump();
    expect(find.text('MUTED'), findsOneWidget);
    expect(find.text('UNMUTE'), findsOneWidget);
  });

  for (final (size, wide) in sizes) {
    testWidgets('menu lays out at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      final game = await makeGame();
      game.wide = wide;
      await pumpAt(tester, size, MenuOverlay(game: game));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dailyButton')), findsOneWidget);
      expect(find.byKey(const Key('endlessButton')), findsOneWidget);
      // The big button and Endless are fully on screen without scrolling.
      for (final k in ['dailyButton', 'endlessButton']) {
        final r = tester.getRect(find.byKey(Key(k)));
        expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$k at $size');
        expect(r.right, lessThanOrEqualTo(size.width), reason: '$k at $size');
      }
    });

    for (final (score, best, newBest, practice, mode) in [
      (0, 0, false, false, GameMode.endless),
      (7, 12, false, false, GameMode.daily),
      (23, 23, true, false, GameMode.endless),
      (148, 148, true, false, GameMode.daily),
      (9, 9, false, true, GameMode.endless),
    ]) {
      for (final still in [false, true]) {
        testWidgets('game over lays out at ${size.width.toInt()}x${size.height.toInt()} '
            'score $score${newBest ? ' new best' : ''}${practice ? ' practice' : ''}${still ? ' reduce motion' : ''}', (tester) async {
          final game = await makeGame();
          game.wide = wide;
          game.phase = GamePhase.gameOver;
          game.lastResult = RunResult(
            mode: mode,
            score: score,
            reason: score == 0 ? 'You pressed the one that said don\'t' : 'Too slow',
            best: best,
            isNewBest: newBest,
            date: DateTime(2026, 10, 17),
            dailyFirst: mode == GameMode.daily ? 5 : null,
            practice: practice,
          );
          await pumpAt(tester, size, GameOverOverlay(game: game), still: still);
          expect(tester.takeException(), isNull);
          final again = tester.getRect(find.byKey(const Key('againButton')));
          expect(again.bottom, lessThanOrEqualTo(size.height), reason: 'AGAIN visible at $size');
          expect(find.text('$score'), findsWidgets);
          if (newBest) expect(find.text('NEW BEST'), findsOneWidget);
          if (practice) expect(find.textContaining('NOT SAVED'), findsOneWidget);
        });
      }
    }
  }
}
