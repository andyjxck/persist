import 'dart:math' as math;

import '../rounds/registry.dart';
import '../rounds/round.dart';
import 'difficulty.dart';
import 'rng.dart';
import 'run_engine.dart';

/// Which chaos a Story level switches on, and how often. Rolled per round
/// from the level's own seed, so a level plays the same every attempt.
class ChaosRecipe {
  const ChaosRecipe({
    this.shake = 0,
    this.shakeChance = 0,
    this.swapChance = 0,
    this.drift = 0,
    this.driftChance = 0,
    this.invertChance = 0,
    this.blackouts = 0,
    this.blackoutChance = 0,
    this.rotationChance = 0,
  });

  final double shake;
  final double shakeChance;
  final double swapChance;
  final double drift;
  final double driftChance;
  final double invertChance;
  final int blackouts;
  final double blackoutChance;
  final double rotationChance;

  static const none = ChaosRecipe();
}

/// One handcrafted level: a fixed list of rounds, how hard they play, which
/// chaos is on, and the notes either side of it.
class StoryLevel {
  const StoryLevel({
    required this.number,
    required this.title,
    required this.briefing,
    required this.log,
    required this.rounds,
    required this.pace,
    this.chaos = ChaosRecipe.none,
    this.twist,
  });

  /// 1-based.
  final int number;
  final String title;

  /// The note you read before the shift.
  final String briefing;

  /// The line written in the log when you get through it.
  final String log;

  /// Round type ids, in order. Rounds a version of the game doesn't have
  /// are swapped for a close equivalent (see [storyFallbacks]).
  final List<String> rounds;

  /// The first round plays like this round number of Endless; each round
  /// after it is one harder.
  final int pace;
  final ChaosRecipe chaos;

  /// What's new in this level, shown on the level card ("NEW: lights cut out").
  final String? twist;

  int get length => rounds.length;

  /// The level's own seed: fixed, so every attempt is the same shift.
  int get seed => hashString('story-level-$number');
}

/// Rounds that only exist on one version, and what stands in for them on the
/// others (first one the version has wins).
const Map<String, List<String>> storyFallbacks = {
  'flick': ['chase', 'dodger'],
  'both_thumbs': ['key_trap', 'scratch', 'dodger'],
  'scratch': ['hover_hold', 'shrinker'],
  'chase': ['flick', 'dodger'],
  'key_trap': ['both_thumbs', 'scratch', 'decoys'],
  'hover_hold': ['scratch', 'hold_it'],
  'magnet': ['scratch', 'shrinker'],
  'grid': ['decoys', 'colour_liar'],
};

/// The night shift on Panel 7. Ten short levels, each adding a twist.
const List<StoryLevel> storyLevels = [
  StoryLevel(
    number: 1,
    title: 'INDUCTION',
    briefing: 'Panel 7 has one button. Do exactly what the screen says. Nothing more.',
    log: 'Shift 1 complete. Operator followed instructions.',
    rounds: ['press_it', 'dont_press', 'press_it', 'press_n_times', 'hold_it', 'dont_press'],
    pace: 0,
  ),
  StoryLevel(
    number: 2,
    title: 'IT MOVES',
    briefing: 'Maintenance says the button has started to drift. Keep up with it.',
    log: 'Shift 2 complete. Button relocated itself four times.',
    rounds: ['press_it', 'shrinker', 'dont_press', 'dodger', 'decoys', 'press_n_times', 'shrinker'],
    pace: 3,
    chaos: ChaosRecipe(shake: 0.15, shakeChance: 0.4),
    twist: 'Moving targets',
  ),
  StoryLevel(
    number: 3,
    title: 'BAD LABELS',
    briefing: 'Some of the labels on Panel 7 are wrong. Read the words, not the colours.',
    log: 'Shift 3 complete. Labels flagged for replacement. Request denied.',
    rounds: ['colour_liar', 'press_it', 'rewrite', 'decoys', 'colour_liar', 'hold_it', 'rewrite', 'dont_press'],
    pace: 5,
    chaos: ChaosRecipe(shake: 0.25, shakeChance: 0.5, swapChance: 0.25),
    twist: 'Lying labels, swapping buttons',
  ),
  StoryLevel(
    number: 4,
    title: 'KEEP A RECORD',
    briefing: 'You will be asked what happened earlier tonight. Write nothing down.',
    log: 'Shift 4 complete. Operator memory within tolerance.',
    rounds: ['remember_this', 'press_it', 'flash_sequence', 'dont_press', 'recall_this', 'colour_liar', 'rounds_ago', 'decoys'],
    pace: 7,
    chaos: ChaosRecipe(shake: 0.3, shakeChance: 0.5, swapChance: 0.35),
    twist: 'Memory',
  ),
  StoryLevel(
    number: 5,
    title: 'HANDS ON',
    briefing: 'Panel 7 now wants more than a press. Use your hands properly.',
    log: 'Shift 5 complete. Panel surface worn smooth.',
    rounds: ['flick', 'press_it', 'both_thumbs', 'scratch', 'dodger', 'magnet', 'flick', 'press_n_times'],
    pace: 9,
    chaos: ChaosRecipe(shake: 0.35, shakeChance: 0.6, swapChance: 0.3, drift: 0.55, driftChance: 0.45),
    twist: 'Buttons that wander',
  ),
  StoryLevel(
    number: 6,
    title: 'INTERRUPTIONS',
    briefing: 'Ignore anything that pops up. It is not for you. Nothing is for you.',
    log: 'Shift 6 complete. 3 alerts ignored. Correctly.',
    rounds: ['fake_notification', 'press_it', 'fake_loading', 'colour_liar', 'fake_notification', 'decoys', 'hold_it', 'rewrite'],
    pace: 11,
    chaos: ChaosRecipe(shake: 0.45, shakeChance: 0.6, swapChance: 0.35, drift: 0.6, driftChance: 0.35),
    twist: 'Fake alerts',
  ),
  StoryLevel(
    number: 7,
    title: 'LIGHTS OUT',
    briefing: 'The power is unstable tonight. When the lights go, keep your hand where it was.',
    log: 'Shift 7 complete. Power restored. Cause unknown.',
    rounds: ['press_it', 'flash_sequence', 'dodger', 'remember_this', 'rewrite', 'shrinker', 'recall_this', 'decoys'],
    pace: 13,
    chaos: ChaosRecipe(shake: 0.5, shakeChance: 0.6, swapChance: 0.3, blackouts: 1, blackoutChance: 0.8),
    twist: 'Blackouts',
  ),
  StoryLevel(
    number: 8,
    title: 'IT LIES NOW',
    briefing: 'Do not trust a screen that says you have finished. You have not finished.',
    log: 'Shift 8 complete. The panel said well done. It did not mean it.',
    rounds: ['fake_win', 'colour_liar', 'rewrite', 'fake_loading', 'dont_press', 'fake_notification', 'both_thumbs', 'fake_win', 'grid'],
    pace: 15,
    chaos: ChaosRecipe(shake: 0.55, shakeChance: 0.7, swapChance: 0.35, invertChance: 0.4, blackouts: 1, blackoutChance: 0.3),
    twist: 'Fake wins, inverted screens',
  ),
  StoryLevel(
    number: 9,
    title: 'PRESSURE',
    briefing: 'Readings are climbing. The room is tilting. Do not stop.',
    log: 'Shift 9 complete. Readings back to normal. For now.',
    rounds: ['press_n_times', 'shrinker', 'colour_liar', 'calm', 'magnet', 'flash_sequence', 'dodger', 'rewrite', 'hold_it', 'decoys'],
    pace: 18,
    chaos: ChaosRecipe(
      shake: 0.75,
      shakeChance: 0.9,
      swapChance: 0.4,
      drift: 0.7,
      driftChance: 0.4,
      invertChance: 0.3,
      blackouts: 1,
      blackoutChance: 0.4,
      rotationChance: 0.5,
    ),
    twist: 'The room tilts',
  ),
  StoryLevel(
    number: 10,
    title: 'LAST SHIFT',
    briefing: 'Your relief is not coming. Everything at once. Make it to the end.',
    log: 'Shift 10 complete. Panel 7 is yours now. Nobody is coming.',
    rounds: [
      'remember_this',
      'fake_notification',
      'colour_liar',
      'both_thumbs',
      'rewrite',
      'recall_this',
      'fake_win',
      'grid',
      'rounds_ago',
      'flick',
      'dont_press',
      'press_it',
    ],
    pace: 22,
    chaos: ChaosRecipe(
      shake: 1,
      shakeChance: 1,
      swapChance: 0.45,
      drift: 0.8,
      driftChance: 0.4,
      invertChance: 0.4,
      blackouts: 2,
      blackoutChance: 0.5,
      rotationChance: 0.5,
    ),
    twist: 'Everything',
  ),
];

/// A Story level as a run: scripted rounds instead of random ones, a fixed
/// seed, and an end. The rules of each round are the same as everywhere else.
class StoryRunEngine extends RunEngine {
  StoryRunEngine(this.level, {super.platform, bool multiTouch = true})
    : super(mode: GameMode.story, seed: level.seed, types: roundTypesFor(platform, multiTouch: multiTouch)) {
    _script = [for (final id in level.rounds) _resolve(id)];
  }

  final StoryLevel level;
  late final List<RoundType> _script;

  RoundType _resolve(String id) {
    if (id == calmRoundType.id) return calmRoundType;
    for (final candidate in [id, ...?storyFallbacks[id]]) {
      for (final t in types) {
        if (t.id == candidate) return t;
      }
    }
    // Every level only uses rounds each version has, or has a stand-in for.
    return types.first;
  }

  /// The scripted round ids for this version of the game.
  List<String> get scriptIds => [for (final t in _script) t.id];

  @override
  RoundType typeFor(int index) => _script[math.min(index, _script.length - 1)];

  @override
  int difficultyIndexFor(int index) => level.pace + index;

  @override
  bool get isComplete => roundIndex >= level.length;

  @override
  ChaosState chaosFor(int index) {
    if (typeFor(index).id == calmRoundType.id) return const ChaosState(calm: true, tempo: 0.8);
    final n = difficultyIndexFor(index);
    final tempo = 1.0 + math.min(0.9, n * 0.025);
    // The first round of a shift is always clean: a breath before it starts.
    if (index == 0) return ChaosState(tempo: tempo);
    final c = level.chaos;
    final rng = SeededRng.derive(seed, [index, 'story-chaos']);
    final shake = rng.chance(c.shakeChance) ? c.shake : 0.0;
    final swap = rng.chance(c.swapChance);
    final drift = rng.chance(c.driftChance) ? c.drift : 0.0;
    final invert = rng.chance(c.invertChance);
    final blackouts = rng.chance(c.blackoutChance) ? c.blackouts : 0;
    var rotation = 0.0;
    if (rng.chance(c.rotationChance)) {
      final speed = rng.rangeDouble(0.12, 0.22);
      rotation = rng.chance(0.5) ? speed : -speed;
    }
    return ChaosState(
      shake: shake,
      invert: invert,
      rotationSpeed: rotation,
      swap: swap,
      tempo: tempo,
      drift: drift,
      blackouts: blackouts,
    );
  }

  /// Story levels announce themselves, not new round families.
  @override
  List<RoundFamily> familiesUnlockingAt(int index) => const [];
}

/// Level [number] (1-based), or null.
StoryLevel? storyLevel(int number) => number >= 1 && number <= storyLevels.length ? storyLevels[number - 1] : null;
