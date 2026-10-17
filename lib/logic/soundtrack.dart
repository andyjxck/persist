import 'dart:math' as math;

/// The soundtrack: one driving loop that starts when a run starts and plays
/// without a break until the run is over. Rounds never restart it; they only
/// push it harder. This file is the pure maths of how hard it pushes, so it
/// is tested on its own. The notes themselves are synthesised by the page's
/// Web Audio player (web/index.html, bpSound.music).
class Soundtrack {
  /// Tempo at the first round, how much each round adds, and the ceiling.
  static const startBpm = 116.0;
  static const bpmPerRound = 2.2;
  static const maxBpm = 172.0;

  /// Below this share of a round's time left, the music starts to panic.
  static const urgentBelow = 0.4;

  /// Tempo for round [roundIndex] (0-based). Only ever goes up within a run.
  static double bpmFor(int roundIndex) => math.min(maxBpm, startBpm + math.max(0, roundIndex) * bpmPerRound);

  /// How many layers are playing:
  /// 0 kick, bass and a quiet off-beat hat;
  /// 1 hats on every eighth, brighter bass (round 3);
  /// 2 sixteenth hats and a clap on 2 and 4 (round 5, when chaos starts);
  /// 3 a tense arpeggio on top (round 8);
  /// 4 a dissonant drone underneath (round 11);
  /// 5 everything doubled up, extra kicks (round 16).
  static int tierFor(int roundIndex) {
    const starts = [0, 2, 4, 7, 10, 15];
    var t = 0;
    for (var i = 0; i < starts.length; i++) {
      if (roundIndex >= starts[i]) t = i;
    }
    return t;
  }

  /// Semitones the key has climbed: one every five rounds, up to six.
  static int keyFor(int roundIndex) => math.min(6, math.max(0, roundIndex) ~/ 5);

  /// 0 while there's plenty of time, rising to 1 at the deadline. Untimed
  /// and calm rounds never panic.
  static double urgencyFor(double timeFraction, {bool timed = true, bool calm = false}) {
    if (!timed || calm) return 0;
    final f = timeFraction.clamp(0.0, 1.0);
    if (f >= urgentBelow) return 0;
    return (urgentBelow - f) / urgentBelow;
  }

  /// The arena pulses on the beat; it pulses harder once the music panics.
  static bool tightBeat(double urgency) => urgency > 0.4;
}

/// Everything the music player needs for one moment of play.
class SoundtrackMix {
  const SoundtrackMix({required this.bpm, required this.tier, required this.key, required this.urgency, required this.calm});

  factory SoundtrackMix.at({required int roundIndex, required double timeFraction, bool timed = true, bool calm = false}) =>
      SoundtrackMix(
        bpm: Soundtrack.bpmFor(roundIndex),
        tier: Soundtrack.tierFor(roundIndex),
        key: Soundtrack.keyFor(roundIndex),
        urgency: Soundtrack.urgencyFor(timeFraction, timed: timed, calm: calm),
        calm: calm,
      );

  final double bpm;
  final int tier;
  final int key;
  final double urgency;
  final bool calm;

  /// Close enough that sending it again would change nothing you can hear.
  bool near(SoundtrackMix? o) =>
      o != null && o.tier == tier && o.key == key && o.calm == calm && (o.bpm - bpm).abs() < 0.05 && (o.urgency - urgency).abs() < 0.02;
}
