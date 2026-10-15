import '../rounds/registry.dart';
import '../rounds/round.dart';
import 'difficulty.dart';
import 'rng.dart';

enum GameMode { daily, endless }

/// What happens after a wrong move.
enum LossOutcome { gameOver, tryAgain }

/// The rules of one run, with no drawing or input: which round comes next,
/// how long it lasts, what chaos is on, and whether a loss is final.
/// Everything is derived from [seed] and the round number, so a Daily run
/// plays out the same for everyone.
class RunEngine {
  RunEngine({
    required this.mode,
    required this.seed,
    List<RoundType>? types,
    this.retryChance = Difficulty.retryChance,
    this.platform = PlayPlatform.touch,
  }) : types = types ?? allRoundTypes;

  /// A Daily run for [date] (local calendar day). Each version of the game
  /// has its own Daily: same for every player on that version.
  factory RunEngine.daily(DateTime date, {PlayPlatform platform = PlayPlatform.touch}) => RunEngine(
    mode: GameMode.daily,
    seed: platformDailySeed(date, platform),
    types: roundTypesFor(platform),
    platform: platform,
  );

  /// An Endless run with a fresh random seed.
  factory RunEngine.endless(int seed, {PlayPlatform platform = PlayPlatform.touch}) =>
      RunEngine(mode: GameMode.endless, seed: seed, types: roundTypesFor(platform), platform: platform);

  static int platformDailySeed(DateTime date, PlayPlatform platform) =>
      platform == PlayPlatform.touch ? dailySeed(date) : (dailySeed(date) ^ hashString('desktop')) & 0xffffffff;

  final PlayPlatform platform;

  /// Play-area width / height, set by the game before each round (geometry
  /// only; it never changes which round comes next).
  double aspect = 0.75;

  final GameMode mode;
  final int seed;
  final List<RoundType> types;

  /// Chance that a loss becomes a TRY AGAIN (only changed by demo mode).
  double retryChance;

  /// 0-based index of the current round. Also the score so far.
  int roundIndex = 0;

  /// Surprise retries used on the current round.
  int retries = 0;

  /// Surprise retries over the whole run (for the result screen).
  int totalRetries = 0;

  final List<RoundRecord> history = [];

  /// Score = rounds survived.
  int get score => roundIndex;

  /// The round type for [index]. Depends only on seed and index.
  RoundType typeFor(int index) {
    if (ChaosState.isCalmRound(seed, index)) return calmRoundType;
    final candidates = <RoundType>[];
    final weights = <double>[];
    for (final t in types) {
      if (index < t.unlockRound) continue;
      // History length always equals the round index, so this is deterministic.
      if (!t.isEligible(_historyStub(index))) continue;
      final w = t.weight(index);
      if (w <= 0) continue;
      candidates.add(t);
      weights.add(w);
    }
    final rng = SeededRng.derive(seed, [index, 'type']);
    var roll = rng.nextDouble() * weights.fold(0.0, (a, b) => a + b);
    for (var i = 0; i < candidates.length; i++) {
      roll -= weights[i];
      if (roll < 0) return candidates[i];
    }
    return candidates.last;
  }

  List<RoundRecord> _historyStub(int index) =>
      index == history.length ? history : List.filled(index, const RoundRecord(typeId: '', colour: GameColour.red));

  ChaosState chaosFor(int index) => ChaosState.forRound(seed, index);

  double timerFactorFor(int index, {int retries = 0}) => Difficulty.timerFactor(index, retries: retries);

  /// Builds the current round. Calling it again after a TRY AGAIN rebuilds the
  /// same round (same buttons, same tricks) with a shorter timer.
  Round startRound() {
    final type = typeFor(roundIndex);
    final ctx = RoundContext(
      roundIndex: roundIndex,
      rng: SeededRng.derive(seed, [roundIndex, 'round', type.id]),
      history: List.unmodifiable(history),
      timerFactor: timerFactorFor(roundIndex, retries: retries),
      platform: platform,
      aspect: aspect,
    );
    return type.create(ctx);
  }

  /// Call when the current round was survived.
  void completeRound(Round round) {
    history.add(RoundRecord(typeId: typeFor(roundIndex).id, colour: round.rememberedColour));
    roundIndex++;
    retries = 0;
  }

  /// Call on a wrong move. About [retryChance] of the time it's a surprise
  /// TRY AGAIN (the round restarts with a shorter timer); otherwise it's over.
  LossOutcome registerLoss() {
    final rng = SeededRng.derive(seed, [roundIndex, 'retry', retries]);
    if (rng.chance(retryChance)) {
      retries++;
      totalRetries++;
      return LossOutcome.tryAgain;
    }
    return LossOutcome.gameOver;
  }

  /// Jumps straight to round [index] by surviving every round before it
  /// (used by the hidden practice/demo link, never by real runs).
  void skipTo(int index) {
    while (roundIndex < index) {
      completeRound(startRound());
    }
  }

  /// Families whose first round type unlocks exactly at [index] (for the
  /// "NEW: Liars" banner).
  List<RoundFamily> familiesUnlockingAt(int index) {
    final result = <RoundFamily>[];
    for (final family in RoundFamily.values) {
      final unlocks = types.where((t) => t.family == family).map((t) => t.unlockRound);
      if (unlocks.isEmpty) continue;
      final first = unlocks.reduce((a, b) => a < b ? a : b);
      if (first == index && index > 0) result.add(family);
    }
    return result;
  }
}
