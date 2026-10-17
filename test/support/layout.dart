import 'dart:io';

import 'package:button_panic/game/button_panic_game.dart';
import 'package:button_panic/services/leaderboard.dart';
import 'package:button_panic/services/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_leaderboard.dart';

/// The smallest phone the game supports.
const phone = Size(320, 568);

/// A game with sound and buzz off. [boards] switches the leaderboards on
/// with an in-memory server (as if built with a Supabase project).
Future<ButtonPanicGame> makeGame({Map<String, Object> prefs = const {}, FakeLeaderboardApi? boards}) async {
  SharedPreferences.setMockInitialValues({'sound_on': false, 'haptics_on': false, ...prefs});
  final store = await ScoreStore.open();
  return ButtonPanicGame(
    store: store,
    clock: () => DateTime(2026, 10, 17, 15),
    leaderboards: boards == null ? null : Leaderboards(store: store, api: boards),
  );
}

/// Pumps [child] alone at [size] (logical pixels) and lets it settle.
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

/// Real type, not the test font, so widths are what players see.
Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Anton', ['Anton-Regular.ttf']);
  await family('Manrope', ['Manrope-Medium.ttf', 'Manrope-SemiBold.ttf', 'Manrope-Bold.ttf', 'Manrope-ExtraBold.ttf']);
}

/// The widget with [key] is entirely inside the screen.
void expectOnScreen(WidgetTester tester, Key key, Size size) {
  final r = tester.getRect(find.byKey(key));
  expect(r.left, greaterThanOrEqualTo(0), reason: '$key left at $size');
  expect(r.top, greaterThanOrEqualTo(0), reason: '$key top at $size');
  expect(r.right, lessThanOrEqualTo(size.width), reason: '$key right at $size');
  expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$key bottom at $size');
}
