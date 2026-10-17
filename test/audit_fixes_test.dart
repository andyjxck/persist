import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/logic/rng.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/rounds/desktop_rounds.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:button_panic/services/storage.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MagnetRound magnet() => MagnetRound(
  RoundContext(
    roundIndex: 12,
    rng: SeededRng(7),
    history: const [],
    timerFactor: 1,
    platform: PlayPlatform.desktop,
    aspect: 1.6,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Magnet', () {
    test('a cursor resting where the button appears is not caught instantly', () {
      final r = magnet();
      // Cursor still sitting where the last round's button was: dead on it.
      r.onHover(r.button.x, r.button.y);
      for (var i = 0; i < 24; i++) {
        r.update(1 / 60); // 0.4 s
      }
      expect(r.verdict, Verdict.pending, reason: r.failReason);
    });

    test('it still catches a cursor that stays put', () {
      final r = magnet();
      r.onHover(r.button.x, r.button.y);
      while (r.verdict == Verdict.pending && r.elapsed < r.timeLimit) {
        r.update(1 / 60);
      }
      expect(r.verdict, Verdict.fail);
      expect(r.failReason, 'It caught your cursor.');
    });
  });

  group('Daily score date', () {
    test('a Daily that ends after midnight is saved to the day it started', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ScoreStore.open();
      var now = DateTime(2026, 10, 17, 23, 59, 50);
      final game = ButtonPanicGame(store: store, clock: () => now);
      game.haptics.enabled = false;
      for (final o in ['menu', 'gameOver']) {
        game.overlays.addEntry(o, (_, _) => const SizedBox());
      }
      game.onGameResize(Vector2(390, 844));
      await game.onLoad();
      game.startRun(GameMode.daily);
      now = DateTime(2026, 10, 18, 0, 0, 30); // midnight passes mid-run
      // Press nothing: rounds time out until the run is over.
      for (var i = 0; i < 60 * 120 && game.phase != GamePhase.gameOver; i++) {
        game.update(1 / 60);
      }
      expect(game.phase, GamePhase.gameOver);
      expect(store.dailyFor(DateTime(2026, 10, 17)), isNotNull);
      expect(store.dailyFor(DateTime(2026, 10, 18)), isNull, reason: "the 18th's Daily hasn't been played");
      expect(game.lastResult!.date.day, 17);
    });

    test('the desktop and phone Dailies keep separate scores', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ScoreStore.open();
      final day = DateTime(2026, 10, 17);
      await store.recordDaily(day, 4, variant: 'desktop');
      expect(store.dailyFor(day), isNull, reason: "the phone Daily hasn't been played");
      await store.recordDaily(day, 11);
      expect(store.dailyFor(day, variant: 'desktop')?.firstScore, 4);
      expect(store.dailyFor(day)?.firstScore, 11);
    });

    test('a desktop Daily is saved under the desktop Daily', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ScoreStore.open();
      final game = ButtonPanicGame(store: store, clock: () => DateTime(2026, 10, 17, 12));
      game.haptics.enabled = false;
      game.wide = true;
      for (final o in ['menu', 'gameOver']) {
        game.overlays.addEntry(o, (_, _) => const SizedBox());
      }
      game.onGameResize(Vector2(1400, 900));
      await game.onLoad();
      game.startRun(GameMode.daily);
      for (var i = 0; i < 60 * 120 && game.phase != GamePhase.gameOver; i++) {
        game.update(1 / 60);
      }
      expect(game.phase, GamePhase.gameOver);
      expect(store.dailyFor(DateTime(2026, 10, 17), variant: 'desktop'), isNotNull);
      expect(store.dailyFor(DateTime(2026, 10, 17)), isNull);
    });

    test("an older day's result never overwrites a newer one", () async {
      SharedPreferences.setMockInitialValues({});
      final store = await ScoreStore.open();
      await store.recordDaily(DateTime(2026, 10, 18), 5);
      await store.recordDaily(DateTime(2026, 10, 17), 9);
      final r = store.dailyFor(DateTime(2026, 10, 18));
      expect(r?.firstScore, 5);
      expect(r?.bestScore, 5);
    });
  });
}
