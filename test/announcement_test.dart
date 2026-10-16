import 'dart:ui';

import 'package:button_panic/game/arena_layout.dart';
import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Announcements ("NEW: LIARS", "TRY AGAIN") used to drop down over the
/// instruction. They now live in their own strip and must never cover the
/// instruction, the timer or the button.
void main() {
  const phones = [Size(320, 568), Size(360, 640), Size(390, 844), Size(430, 932), Size(600, 900), Size(820, 1180)];
  const desktops = [Size(1024, 640), Size(1280, 720), Size(1440, 900), Size(1920, 1080), Size(2560, 1440)];
  // The round number's width: "01" up to "120  PRACTICE".
  const hudWidths = [18.0, 40.0, 90.0, 140.0];

  void checkLayout(ArenaLayout l, double hud) {
    final banner = l.bannerRect(hud);
    final what = '${l.screen} wide=${l.wide} hud=$hud';
    // Above the instruction, with room to spare for the scene shaking.
    expect(banner.bottom + ArenaLayout.maxPlayShake, lessThanOrEqualTo(l.instructionRect.top), reason: what);
    expect(banner.overlaps(l.instructionRect), isFalse, reason: what);
    // Nowhere near the buttons and their timer rings.
    expect(banner.overlaps(l.playRect), isFalse, reason: what);
    expect(banner.bottom, lessThan(l.playRect.top), reason: what);
    // Clear of the round number on the left...
    expect(banner.left, greaterThanOrEqualTo(l.columnRect.left + l.pad + hud), reason: what);
    // ...and of the SOUND word at the phone's top right.
    if (!l.wide) {
      expect(banner.right, lessThanOrEqualTo(l.columnRect.right - ArenaLayout.phoneSoundRoom), reason: what);
    }
    expect(banner.top, greaterThanOrEqualTo(0), reason: what);
  }

  group('Announcement strip', () {
    test('never overlaps the instruction, the timer or the button on any phone', () {
      for (final s in phones) {
        for (final h in hudWidths) {
          checkLayout(ArenaLayout(s, wide: false), h);
        }
      }
    });

    test('never overlaps the instruction, the timer or the button on desktop', () {
      for (final s in desktops) {
        for (final h in hudWidths) {
          checkLayout(ArenaLayout(s, wide: true), h);
        }
      }
    });

    test('the shake while playing stays inside the margin the strip leaves', () {
      expect(ButtonPanicGame.chaosShakePx + ButtonPanicGame.deadlineTremorPx, lessThanOrEqualTo(ArenaLayout.maxPlayShake));
    });
  });

  group('When announcements show', () {
    late ButtonPanicGame game;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      game = ButtonPanicGame(store: await ScoreStore.open());
      game.banner = 'NEW: Liars';
      game.bannerTime = 1.6;
      game.bannerDuration = 1.6;
    });

    test('shows in its strip while the scene is upright', () {
      game.phase = GamePhase.playing;
      game.rotation = 0;
      expect(game.bannerShowing, isTrue);
    });

    test('is held back while a rotating round could swing into the strip', () {
      game.phase = GamePhase.playing;
      game.rotation = 0.3;
      expect(game.bannerShowing, isFalse);
      game.rotation = -0.01;
      expect(game.bannerShowing, isFalse);
    });

    test('never shows on the menu, while failing or over the game-over screen', () {
      for (final p in [GamePhase.menu, GamePhase.failing, GamePhase.fakeGameOver, GamePhase.gameOver]) {
        game.phase = p;
        game.rotation = 0;
        expect(game.bannerShowing, isFalse, reason: '$p');
      }
    });

    test('an empty or finished announcement shows nothing', () {
      game.phase = GamePhase.playing;
      game.bannerTime = 0;
      expect(game.bannerShowing, isFalse);
      game.bannerTime = 1;
      game.banner = '';
      expect(game.bannerShowing, isFalse);
    });
  });
}
