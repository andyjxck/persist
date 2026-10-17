import 'package:button_panic/logic/difficulty.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/logic/story.dart';
import 'package:button_panic/rounds/registry.dart';
import 'package:button_panic/rounds/round.dart';
import 'package:flutter_test/flutter_test.dart';

// Story mode's rules: ten fixed shifts that get harder, play the same every
// attempt, only use rounds each version of the game has (or a named stand-in)
// and end after their last round.

List<Object> _chaosKey(ChaosState c) => [c.shake, c.invert, c.rotationSpeed, c.swap, c.tempo, c.calm, c.drift, c.blackouts];

const _versions = [(PlayPlatform.desktop, true, 'desktop'), (PlayPlatform.touch, true, 'phone'), (PlayPlatform.touch, false, 'phone with a mouse only')];

void main() {
  test('there are ten shifts, numbered 1 to 10, each with a title, briefing, log and rounds', () {
    expect(storyLevels, hasLength(10));
    for (var i = 0; i < storyLevels.length; i++) {
      final lv = storyLevels[i];
      expect(lv.number, i + 1);
      expect(lv.title.trim(), isNotEmpty);
      expect(lv.briefing.trim(), isNotEmpty);
      expect(lv.log.trim(), isNotEmpty);
      expect(lv.length, greaterThanOrEqualTo(6), reason: lv.title);
      expect(lv.length, lessThanOrEqualTo(12), reason: lv.title);
      // Every shift after the first says what is new in it.
      if (lv.number > 1) expect(lv.twist, isNotNull, reason: lv.title);
    }
    expect(storyLevel(0), isNull);
    expect(storyLevel(11), isNull);
    expect(storyLevel(3)!.title, storyLevels[2].title);
  });

  test('each shift starts harder than the one before, and every shift has its own fixed seed', () {
    for (var i = 1; i < storyLevels.length; i++) {
      expect(storyLevels[i].pace, greaterThan(storyLevels[i - 1].pace), reason: storyLevels[i].title);
    }
    final seeds = {for (final lv in storyLevels) lv.seed};
    expect(seeds, hasLength(storyLevels.length));
    expect(storyLevels.first.seed, storyLevels.first.seed);
  });

  for (final (platform, multiTouch, name) in _versions) {
    test('on the $name version every scripted round is the round itself or one of its named stand-ins', () {
      final available = {for (final t in roundTypesFor(platform, multiTouch: multiTouch)) t.id};
      for (final lv in storyLevels) {
        final e = StoryRunEngine(lv, platform: platform, multiTouch: multiTouch);
        final ids = e.scriptIds;
        expect(ids, hasLength(lv.length));
        for (var i = 0; i < lv.length; i++) {
          final wanted = lv.rounds[i];
          final got = ids[i];
          if (wanted == calmRoundType.id) {
            expect(got, calmRoundType.id);
            continue;
          }
          // Never the silent "first round type" fallback.
          expect([wanted, ...?storyFallbacks[wanted]], contains(got), reason: 'shift ${lv.number} round ${i + 1}: $wanted -> $got');
          expect(available.contains(got) || got == calmRoundType.id, isTrue, reason: got);
          // The first stand-in this version has is the one used.
          if (!available.contains(wanted)) {
            final first = storyFallbacks[wanted]!.firstWhere(available.contains);
            expect(got, first, reason: 'shift ${lv.number} round ${i + 1}');
          }
        }
      }
    });
  }

  test('a shift plays the same rounds and the same chaos on every attempt', () {
    for (final lv in storyLevels) {
      final a = StoryRunEngine(lv, platform: PlayPlatform.desktop);
      final b = StoryRunEngine(lv, platform: PlayPlatform.desktop);
      expect(a.seed, lv.seed);
      expect(a.mode, GameMode.story);
      expect(a.scriptIds, b.scriptIds);
      for (var i = 0; i < lv.length; i++) {
        expect(_chaosKey(a.chaosFor(i)), _chaosKey(b.chaosFor(i)), reason: 'shift ${lv.number} round ${i + 1}');
        expect(a.typeFor(i).id, b.typeFor(i).id);
      }
    }
  });

  test('the first round of every shift is clean, and chaos never goes past what the shift allows', () {
    for (final lv in storyLevels) {
      final e = StoryRunEngine(lv, platform: PlayPlatform.touch);
      final first = e.chaosFor(0);
      expect(first.shake, 0, reason: lv.title);
      expect(first.swap, isFalse);
      expect(first.invert, isFalse);
      expect(first.drift, 0);
      expect(first.blackouts, 0);
      expect(first.rotationSpeed, 0);
      for (var i = 1; i < lv.length; i++) {
        final c = e.chaosFor(i);
        if (c.calm) continue;
        expect(c.shake, lessThanOrEqualTo(lv.chaos.shake), reason: '${lv.title} round ${i + 1}');
        expect(c.drift, lessThanOrEqualTo(lv.chaos.drift));
        expect(c.blackouts, lessThanOrEqualTo(lv.chaos.blackouts));
        if (lv.chaos.swapChance == 0) expect(c.swap, isFalse);
        if (lv.chaos.invertChance == 0) expect(c.invert, isFalse);
        if (lv.chaos.rotationChance == 0) expect(c.rotationSpeed, 0);
      }
    }
    // Shift 1 has no chaos at all.
    final one = StoryRunEngine(storyLevels.first);
    for (var i = 0; i < one.level.length; i++) {
      expect(one.chaosFor(i).activeLayers, isEmpty);
    }
  });

  test('the calm round in shift 9 is calm, and difficulty is the shift pace plus the round', () {
    final lv = storyLevel(9)!;
    final e = StoryRunEngine(lv, platform: PlayPlatform.desktop);
    final calmAt = lv.rounds.indexOf(calmRoundType.id);
    expect(calmAt, greaterThan(0));
    expect(e.chaosFor(calmAt).calm, isTrue);
    for (var i = 0; i < lv.length; i++) {
      expect(e.difficultyIndexFor(i), lv.pace + i);
    }
  });

  test('a shift is complete after its last round and not before', () {
    for (final (platform, multiTouch, _) in _versions) {
      final lv = storyLevel(2)!;
      final e = StoryRunEngine(lv, platform: platform, multiTouch: multiTouch);
      for (var i = 0; i < lv.length; i++) {
        expect(e.isComplete, isFalse, reason: 'after ${e.roundIndex} rounds');
        final r = e.startRound();
        expect(e.typeFor(i).id, e.scriptIds[i]);
        e.completeRound(r);
      }
      expect(e.isComplete, isTrue);
      expect(e.score, lv.length);
    }
  });

  test('story never announces new round families', () {
    final e = StoryRunEngine(storyLevel(4)!);
    for (var i = 0; i < e.level.length; i++) {
      expect(e.familiesUnlockingAt(i), isEmpty);
    }
  });
}
