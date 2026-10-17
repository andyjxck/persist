import 'dart:math' as math;

import 'rng.dart';

/// All the tuning numbers in one place.
class Difficulty {
  /// Each round's timer is this much of the previous one...
  static const double timerDecay = 0.965;

  /// ...but never below this fraction of the starting time.
  static const double timerFloor = 0.4;

  /// After a surprise TRY AGAIN, the retried round gets this much of the time.
  static const double retryTimerMultiplier = 0.6;

  /// Chance that a loss turns into TRY AGAIN instead of game over.
  static const double retryChance = 0.02;

  /// How long the fake game-over screen stays up before the reveal.
  static const double fakeGameOverSeconds = 0.5;

  /// Timer multiplier for a round (0-based), after [retries] surprise retries.
  static double timerFactor(int roundIndex, {int retries = 0}) {
    final base = math.max(timerFloor, math.pow(timerDecay, roundIndex).toDouble());
    return base * math.pow(retryTimerMultiplier, retries).toDouble();
  }
}

/// Which chaos layers are switched on for a round. They stack as you survive.
class ChaosState {
  const ChaosState({
    this.shake = 0,
    this.invert = false,
    this.rotationSpeed = 0,
    this.swap = false,
    this.tempo = 1,
    this.calm = false,
    this.drift = 0,
    this.blackouts = 0,
  });

  /// Screen shake strength, 0..1.
  final double shake;

  /// Colour inversion.
  final bool invert;

  /// Slow screen rotation, radians per second (0 = off, sign = direction).
  final double rotationSpeed;

  /// Buttons swap places mid-round.
  final bool swap;

  /// Music speed multiplier.
  final double tempo;

  /// A suspiciously calm round: everything above is switched off.
  final bool calm;

  /// Buttons wander around their spot while you aim, 0..1 (how far).
  final double drift;

  /// How many times the lights cut out for a split second mid-round.
  final int blackouts;

  static const none = ChaosState();

  List<String> get activeLayers => [
    if (shake > 0) 'shake',
    if (invert) 'invert',
    if (rotationSpeed != 0) 'rotate',
    if (swap) 'swap',
    if (drift > 0) 'drift',
    if (blackouts > 0) 'blackout',
    if (calm) 'calm',
  ];

  /// Chaos for [roundIndex] in the run with [seed]. Deterministic.
  static ChaosState forRound(int seed, int roundIndex) {
    if (isCalmRound(seed, roundIndex)) {
      return const ChaosState(calm: true, tempo: 0.8);
    }
    final rng = SeededRng.derive(seed, [roundIndex, 'chaos']);
    final n = roundIndex;
    final double tempo = 1 + math.min(0.9, n * 0.025);

    // Chaos starts early and piles up: by round 12 most rounds stack two or
    // three layers, and from round 16 the screen never stops shaking.
    var shake = 0.0;
    if (n >= 3 && (n >= 12 || rng.chance(0.55))) {
      shake = math.min(1.0, (n - 2) / 16);
    }
    final swap = n >= 5 && rng.chance(math.min(0.6, 0.35 + (n - 5) * 0.015));
    var drift = 0.0;
    if (n >= 6 && rng.chance(math.min(0.6, 0.3 + (n - 6) * 0.015))) {
      drift = math.min(1.0, 0.45 + (n - 6) * 0.03);
    }
    final invert = n >= 8 && rng.chance(math.min(0.45, 0.2 + (n - 8) * 0.012));
    var blackouts = 0;
    if (n >= 9 && rng.chance(math.min(0.5, 0.25 + (n - 9) * 0.015))) {
      blackouts = n >= 18 && rng.chance(0.5) ? 2 : 1;
    }
    var rotation = 0.0;
    if (n >= 12 && rng.chance(math.min(0.5, 0.25 + (n - 12) * 0.01))) {
      final speed = rng.rangeDouble(0.12, 0.2 + math.min(0.3, (n - 12) * 0.01));
      rotation = rng.chance(0.5) ? speed : -speed;
    }
    return ChaosState(shake: shake, invert: invert, rotationSpeed: rotation, swap: swap, tempo: tempo, drift: drift, blackouts: blackouts);
  }

  static bool _rawCalm(int seed, int roundIndex) {
    if (roundIndex < 8) return false;
    return SeededRng.derive(seed, [roundIndex, 'calm']).chance(0.08);
  }

  /// Calm rounds never come two in a row.
  static bool isCalmRound(int seed, int roundIndex) => _rawCalm(seed, roundIndex) && !_rawCalm(seed, roundIndex - 1);
}
