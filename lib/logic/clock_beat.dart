import 'dart:math' as math;

/// The tick-tock that drives every round: how far apart the beats are and
/// when they turn tight. Pure maths, so it is tested on its own.
class ClockBeat {
  /// Beat spacing at the start of the first round (tick, tock: 120 a minute).
  static const firstRound = 0.5;

  /// The start-of-round spacing never gets shorter than this as rounds go on.
  static const lateRound = 0.3;

  /// The fastest the clock ever runs, in the last moments of a round.
  static const fastest = 0.085;

  /// Below this share of time left the clock switches to its tight beat.
  static const tightBelow = 0.25;

  /// Spacing at the start of round [roundIndex] (0-based): it tightens a
  /// little every round, so a long run feels faster from the first beat.
  static double roundBase(int roundIndex) => math.max(lateRound, firstRound - roundIndex * 0.008);

  /// Seconds until the next beat.
  ///
  /// [timeFraction] is the share of the round's time still left (1 at the
  /// start, 0 at the deadline). Untimed rounds keep the round's base beat;
  /// calm rounds slow right down.
  static double interval({required double timeFraction, required int roundIndex, bool timed = true, bool calm = false}) {
    final base = roundBase(roundIndex);
    if (calm) return base * 1.7;
    if (!timed) return base;
    final f = timeFraction.clamp(0.0, 1.0);
    return fastest + (base - fastest) * math.pow(f, 1.35);
  }

  static bool tight({required double timeFraction, bool timed = true, bool calm = false}) =>
      timed && !calm && timeFraction < tightBelow;
}
