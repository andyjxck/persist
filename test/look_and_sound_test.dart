import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:button_panic/rounds/round.dart';
import 'package:button_panic/services/feedback.dart';
import 'package:button_panic/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _distance(Color a, Color b) {
  final dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

void main() {
  group('Colour rounds stay readable on paper', () {
    test('every button is outlined in ink that stands out from every background, and every colour stands out from its outline', () {
      for (final bg in [BP.ink, BP.calmBg, BP.flood]) {
        expect(_contrast(BP.paper, bg), greaterThan(7), reason: '$bg');
      }
      for (final c in GameColour.all) {
        expect(_contrast(c.color, BP.paper), greaterThan(3), reason: c.name);
      }
    });

    test('every pair of button colours is clearly different', () {
      final all = GameColour.all;
      for (var i = 0; i < all.length; i++) {
        for (var j = i + 1; j < all.length; j++) {
          expect(_distance(all[i].color, all[j].color), greaterThan(90), reason: '${all[i].name} vs ${all[j].name}');
        }
      }
    });
  });

  group('Sound set', () {
    test('every sound the game plays exists and is small, and the soundtrack is synthesised live (no music file to download)', () {
      var total = 0;
      for (final f in GameAudio.files) {
        final file = File('assets/audio/$f');
        expect(file.existsSync(), isTrue, reason: f);
        total += file.lengthSync();
        expect(file.lengthSync(), lessThan(24 * 1024), reason: f);
      }
      expect(total, lessThan(64 * 1024));
      expect(File('assets/audio/loop.wav').existsSync(), isFalse);
    });

    test('the clock sounds are short and dry', () {
      for (final f in [GameAudio.tick, GameAudio.tock, GameAudio.tickTight, GameAudio.tockTight, GameAudio.press]) {
        final bytes = File('assets/audio/$f').lengthSync();
        // 22.05 kHz mono 16-bit: under 100 ms is under ~4.5 KB.
        expect(bytes, lessThan(4500), reason: f);
      }
    });
  });
}
