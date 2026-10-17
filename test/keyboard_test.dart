import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/logic/rng.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/rounds/desktop_rounds.dart';
import 'package:button_panic/rounds/registry.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:button_panic/services/storage.dart';
import 'package:button_panic/ui/web_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Real key presses on the desktop web page, sent the way a browser sends
// them: nothing here moves the keyboard focus by hand, so if anything (like
// Flame's GameWidget) grabs it and swallows keys, these fail.

Future<ButtonPanicGame> pumpWeb(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'sound_on': false, 'haptics_on': false});
  final store = await ScoreStore.open();
  final game = ButtonPanicGame(store: store);
  game.wide = true;
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: WebPage(game: game, gameKey: GlobalKey())));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return game;
}

KeyTrapRound keyRound({required bool handsOff}) {
  for (var seed = 1; seed < 500; seed++) {
    final r = KeyTrapRound(
      RoundContext(
        roundIndex: handsOff ? 20 : 0,
        rng: SeededRng(seed),
        history: const [],
        timerFactor: 100,
        platform: PlayPlatform.desktop,
      ),
    );
    if (r.handsOff == handsOff) return r;
  }
  throw StateError('no key trap round with handsOff=$handsOff');
}

LogicalKeyboardKey keyFor(String letter) =>
    LogicalKeyboardKey.findKeyByKeyId(LogicalKeyboardKey.keyA.keyId + (letter.codeUnitAt(0) - 65))!;

Future<KeyTrapRound> startKeyRound(WidgetTester tester, ButtonPanicGame game, {bool handsOff = false}) async {
  final r = keyRound(handsOff: handsOff);
  game.debugSetRound(r);
  game.phase = GamePhase.playing;
  await tester.pump();
  return r;
}

void main() {
  testWidgets('the game canvas never takes the keyboard from the page', (tester) async {
    await pumpWeb(tester);
    final primary = FocusManager.instance.primaryFocus;
    expect(primary?.debugLabel, 'page');
  });

  testWidgets('menu: Space starts the Daily', (tester) async {
    final game = await pumpWeb(tester);
    expect(game.phase, GamePhase.menu);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.phase, isNot(GamePhase.menu));
    expect(game.engine?.mode, GameMode.daily);
  });

  testWidgets('menu: E starts Endless', (tester) async {
    final game = await pumpWeb(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.engine?.mode, GameMode.endless);
  });

  testWidgets('M mutes on the menu', (tester) async {
    final game = await pumpWeb(tester);
    final before = game.audio.enabled;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(game.audio.enabled, !before);
  });

  testWidgets('key trap: pressing the right letter wins', (tester) async {
    final game = await pumpWeb(tester);
    final r = await startKeyRound(tester, game);
    await tester.sendKeyEvent(keyFor(r.letter));
    await tester.pump(const Duration(milliseconds: 16));
    expect(r.verdict, Verdict.success, reason: r.failReason);
  });

  testWidgets('key trap: Shift + the letter (a capital) still wins', (tester) async {
    final game = await pumpWeb(tester);
    final r = await startKeyRound(tester, game);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(keyFor(r.letter));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 16));
    expect(r.verdict, Verdict.success, reason: r.failReason);
  });

  testWidgets('key trap: Caps Lock, Alt, Ctrl and Cmd on their own are not answers', (tester) async {
    final game = await pumpWeb(tester);
    final r = await startKeyRound(tester, game);
    for (final k in [
      LogicalKeyboardKey.capsLock,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyEvent(k);
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(r.verdict, Verdict.pending, reason: r.failReason);
  });

  testWidgets('key trap: the wrong letter loses', (tester) async {
    final game = await pumpWeb(tester);
    final r = await startKeyRound(tester, game);
    final wrong = r.letter == 'Q' ? 'W' : 'Q';
    await tester.sendKeyEvent(keyFor(wrong));
    await tester.pump(const Duration(milliseconds: 16));
    expect(r.verdict, Verdict.fail);
    expect(r.failReason, contains('not ${r.letter}'));
  });

  testWidgets('M mid-round mutes and does not count as a wrong key', (tester) async {
    final game = await pumpWeb(tester);
    final r = await startKeyRound(tester, game);
    final before = game.audio.enabled;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.audio.enabled, !before);
    expect(r.verdict, Verdict.pending);
  });

  testWidgets('hands-off round: touching the keyboard loses', (tester) async {
    final game = await pumpWeb(tester);
    final r = await startKeyRound(tester, game, handsOff: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 16));
    expect(r.verdict, Verdict.fail);
  });

  testWidgets('keys still work after clicking the game', (tester) async {
    final game = await pumpWeb(tester);
    final r = await startKeyRound(tester, game);
    // Click empty space on the stage (not the button).
    await tester.tapAt(const Offset(10, 890));
    await tester.pump(const Duration(milliseconds: 16));
    expect(r.verdict, Verdict.pending, reason: r.failReason);
    await tester.sendKeyEvent(keyFor(r.letter));
    await tester.pump(const Duration(milliseconds: 16));
    expect(r.verdict, Verdict.success, reason: r.failReason);
  });

  testWidgets('game over: R plays again and Esc goes back to the menu', (tester) async {
    final game = await pumpWeb(tester);
    game.phase = GamePhase.gameOver;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.phase, GamePhase.menu);
    game.phase = GamePhase.gameOver;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.phase, isNot(GamePhase.gameOver));
    expect(game.phase, isNot(GamePhase.menu));
  });

  test('mouse-only phone layout leaves out the two-thumb round', () {
    final ids = roundTypesFor(PlayPlatform.touch, multiTouch: false).map((t) => t.id).toList();
    expect(ids, isNot(contains('both_thumbs')));
    expect(ids, contains('flick'));
    final full = roundTypesFor(PlayPlatform.touch).map((t) => t.id).toList();
    expect(full, contains('both_thumbs'));
    // The usual pools don't change, so nobody's Daily shifts.
    expect(roundTypesFor(PlayPlatform.desktop).map((t) => t.id), contains('key_trap'));
  });
}
