import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/logic/soundtrack.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:button_panic/services/storage.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Soundtrack builds as the run goes on', () {
    test('tempo, layers and key only ever go up from round to round', () {
      for (var r = 1; r < 200; r++) {
        expect(Soundtrack.bpmFor(r), greaterThanOrEqualTo(Soundtrack.bpmFor(r - 1)), reason: 'round $r');
        expect(Soundtrack.tierFor(r), greaterThanOrEqualTo(Soundtrack.tierFor(r - 1)), reason: 'round $r');
        expect(Soundtrack.keyFor(r), greaterThanOrEqualTo(Soundtrack.keyFor(r - 1)), reason: 'round $r');
      }
      expect(Soundtrack.bpmFor(0), Soundtrack.startBpm);
      expect(Soundtrack.bpmFor(10), greaterThan(Soundtrack.bpmFor(0) + 15));
      expect(Soundtrack.bpmFor(500), Soundtrack.maxBpm);
      expect(Soundtrack.tierFor(0), 0);
      expect(Soundtrack.tierFor(4), 2, reason: 'the clap comes in with the chaos');
      expect(Soundtrack.tierFor(20), 5);
    });

    test('it panics only in the last part of a timed round', () {
      expect(Soundtrack.urgencyFor(1), 0);
      expect(Soundtrack.urgencyFor(0.5), 0);
      expect(Soundtrack.urgencyFor(0.2), closeTo(0.5, 1e-9));
      expect(Soundtrack.urgencyFor(0), 1);
      expect(Soundtrack.urgencyFor(0, calm: true), 0);
      expect(Soundtrack.urgencyFor(0, timed: false), 0);
      for (var f = 0.0; f < 1; f += 0.01) {
        expect(Soundtrack.urgencyFor(f), greaterThanOrEqualTo(Soundtrack.urgencyFor(f + 0.01)));
      }
    });
  });

  group('The music never restarts on a level change', () {
    test('one start for a whole run of many rounds, and it keeps building', () async {
      SharedPreferences.setMockInitialValues({});
      final game = ButtonPanicGame(store: await ScoreStore.open(), demo: const DemoConfig(seed: 42));
      game.haptics.enabled = false;
      for (final o in ['menu', 'gameOver']) {
        game.overlays.addEntry(o, (_, _) => const SizedBox());
      }
      game.onGameResize(Vector2(390, 844));
      await game.onLoad();
      game.startRun(GameMode.endless);

      expect(game.audio.musicStarts, 1);
      expect(game.audio.musicPlaying, isTrue);

      final tempos = <double>[];
      var lastRound = -1;
      var roundsSeen = 0;
      // Win 25 rounds in a row, stepping the game at 60 frames a second
      // through each round and the gap between rounds.
      for (var frame = 0; frame < 60 * 120 && roundsSeen < 25; frame++) {
        final r = game.round!;
        if (r.ctx.roundIndex != lastRound) {
          lastRound = r.ctx.roundIndex;
          roundsSeen++;
          expect(game.audio.musicStarts, 1, reason: 'restarted at round ${r.ctx.roundIndex}');
          expect(game.audio.musicStops, 0);
          expect(game.audio.musicPlaying, isTrue);
          expect(game.audio.musicDucked, isFalse);
        }
        if (game.phase == GamePhase.playing && r.verdict == Verdict.pending && r.elapsed > 0.2) {
          r.verdict = Verdict.success;
        }
        game.update(1 / 60);
        final mix = game.audio.lastMix;
        if (mix != null) tempos.add(mix.bpm);
      }

      expect(roundsSeen, 25);
      expect(game.audio.musicStarts, 1);
      expect(game.audio.musicStops, 0);
      for (var i = 1; i < tempos.length; i++) {
        expect(tempos[i], greaterThanOrEqualTo(tempos[i - 1]), reason: 'tempo fell back at a round change');
      }
      expect(tempos.last, greaterThan(tempos.first + 30));

      // Losing drops the music out; the real game over stops it, once.
      game.round!.verdict = Verdict.fail;
      for (var i = 0; i < 60 * 3; i++) {
        game.update(1 / 60);
      }
      expect(game.audio.musicStarts, 1);
      expect(game.phase == GamePhase.gameOver || game.phase == GamePhase.fakeGameOver, isTrue);
      if (game.phase == GamePhase.gameOver) {
        expect(game.audio.musicPlaying, isFalse);
        expect(game.audio.musicStops, 1);
      }

      // A new run is a new start.
      game.startRun(GameMode.endless);
      expect(game.audio.musicStarts, 2);
    });

    test('TRY AGAIN brings the same soundtrack back instead of starting it over', () async {
      SharedPreferences.setMockInitialValues({});
      final game = ButtonPanicGame(store: await ScoreStore.open(), demo: const DemoConfig(seed: 7, forceRetry: true));
      game.haptics.enabled = false;
      for (final o in ['menu', 'gameOver']) {
        game.overlays.addEntry(o, (_, _) => const SizedBox());
      }
      game.onGameResize(Vector2(390, 844));
      await game.onLoad();
      game.startRun(GameMode.endless);
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      game.round!.verdict = Verdict.fail;
      game.update(1 / 60);
      expect(game.audio.musicDucked, isTrue);
      var sawFake = false;
      for (var i = 0; i < 60 * 6 && game.phase != GamePhase.playing; i++) {
        if (game.phase == GamePhase.fakeGameOver) sawFake = true;
        game.update(1 / 60);
      }
      expect(sawFake, isTrue);
      expect(game.phase, GamePhase.playing);
      expect(game.audio.musicStarts, 1);
      expect(game.audio.musicStops, 0);
      expect(game.audio.musicPlaying, isTrue);
      expect(game.audio.musicDucked, isFalse);
    });
  });
}
