import 'dart:ui';

import '../logic/rng.dart';

/// The colours a button can be. Names matter: liar rounds say them out loud.
class GameColour {
  const GameColour(this.name, this.color);
  final String name;
  final Color color;

  static const red = GameColour('RED', Color(0xFFE53935));
  static const blue = GameColour('BLUE', Color(0xFF1E88E5));
  static const green = GameColour('GREEN', Color(0xFF43A047));
  static const yellow = GameColour('YELLOW', Color(0xFFFDD835));
  static const purple = GameColour('PURPLE', Color(0xFF8E24AA));
  static const orange = GameColour('ORANGE', Color(0xFFFB8C00));

  static const all = [red, blue, green, yellow, purple, orange];

  @override
  String toString() => name;
}

/// One button on screen. Positions are normalised to the play area:
/// x and y run from 0 to 1, radius is a fraction of the area's shorter side.
class GameButton {
  GameButton({required this.id, required this.colour, this.label = '', this.x = 0.5, this.y = 0.5, this.radius = 0.22});

  final String id;
  GameColour colour;
  String label;
  double x;
  double y;
  double radius;
  bool visible = true;

  /// Lit up (used by flash sequences).
  bool highlighted = false;

  /// Currently held down by a finger (set by the game, read by rounds).
  bool pressed = false;

  /// 0..1 progress ring drawn around the button (used by "Hold it").
  double ring = 0;
}

enum Verdict { pending, success, fail }

enum FakeKind { loading, win, notification }

/// A fake screen element drawn on top of the round (fake loading screen,
/// fake "you win!", fake notification). Rect is normalised to the whole screen.
class FakeOverlay {
  FakeOverlay({
    required this.id,
    required this.kind,
    required this.rect,
    this.title = '',
    this.body = '',
    this.buttonLabel,
    this.blocksInput = true,
  });

  final String id;
  final FakeKind kind;
  Rect rect;
  String title;
  String body;
  String? buttonLabel;
  double progress = 0;

  /// If true, taps on it go to the round as `overlay id` (usually a mistake).
  /// If false, taps pass straight through to the buttons underneath.
  bool blocksInput;
}

/// What happened in previous rounds, for memory rounds.
class RoundRecord {
  const RoundRecord({required this.typeId, required this.colour});
  final String typeId;

  /// The colour the player should remember for this round.
  final GameColour colour;
}

/// Everything a round needs to build itself. The [rng] is private to this
/// round, derived from the run seed and the round number, so the Daily run
/// is identical for everyone.
class RoundContext {
  RoundContext({required this.roundIndex, required this.rng, required this.history, required this.timerFactor});

  /// 0-based index of this round in the run.
  final int roundIndex;
  final SeededRng rng;
  final List<RoundRecord> history;

  /// Multiplier for this round's time limit (shrinks as the run goes on, and
  /// shrinks again after a surprise TRY AGAIN).
  final double timerFactor;

  /// 0 at the start, rising towards 1 around round 40 and beyond.
  double get difficulty => (roundIndex / 40).clamp(0.0, 1.5);
}

/// Base class for one round. Subclasses describe what's on screen (buttons,
/// instruction, overlays) and react to presses. The game draws whatever a
/// round exposes, so adding a new kind of chaos means writing one class.
abstract class Round {
  Round(this.ctx);

  final RoundContext ctx;

  /// Seconds elapsed in this round (advanced by [update]).
  double elapsed = 0;
  Verdict verdict = Verdict.pending;

  /// Shown on the game-over screen.
  String failReason = '';

  /// The instruction at the top of the screen. May change over time.
  String get instruction;

  /// Optional smaller line under the instruction.
  String get hint => '';

  List<GameButton> get buttons;

  List<FakeOverlay> get overlays => const [];

  /// Base time before multiplying by [RoundContext.timerFactor].
  double get baseTime;

  double get timeLimit => baseTime * ctx.timerFactor;

  bool get showTimer => true;

  /// Calm rounds turn every chaos layer off.
  bool get isCalm => false;

  /// Whether the engine may swap button positions mid-round.
  bool get allowSwap => buttons.length >= 2;

  /// The colour memory rounds will ask about later.
  GameColour get rememberedColour => buttons.first.colour;

  double get timeLeft => (timeLimit - elapsed).clamp(0, timeLimit);

  void update(double dt) {
    if (verdict != Verdict.pending) return;
    elapsed += dt;
    tick(dt);
    if (verdict == Verdict.pending && elapsed >= timeLimit) {
      onTimeout();
    }
  }

  /// Per-frame hook for moving buttons, rewriting text, and so on.
  void tick(double dt) {}

  /// A finger went down on [targetId] (a button id, an overlay id, or null
  /// for empty space).
  void onPressDown(String? targetId) {}

  /// A finger came up. [targetId] is what it went down on.
  void onPressUp(String? targetId) {}

  /// Default: running out of time loses.
  void onTimeout() => fail('Too slow.');

  void succeed() {
    if (verdict == Verdict.pending) verdict = Verdict.success;
  }

  void fail(String reason) {
    if (verdict == Verdict.pending) {
      verdict = Verdict.fail;
      failReason = reason;
    }
  }

  /// Demo autoplay only: what a perfect player would tap right now, or null
  /// to wait. Return `hold:ID` to press button ID and keep holding.
  String? demoMove() => null;
}

/// Families group round types for unlock announcements.
enum RoundFamily { simple, liar, memory, runner, fake, calm }

extension RoundFamilyName on RoundFamily {
  String get title => switch (this) {
    RoundFamily.simple => 'Simple',
    RoundFamily.liar => 'Liars',
    RoundFamily.memory => 'Memory',
    RoundFamily.runner => 'Runners',
    RoundFamily.fake => 'Fakes',
    RoundFamily.calm => 'Calm',
  };
}

/// A pluggable round type. Register new ones in `registry.dart`.
abstract class RoundType {
  const RoundType();

  /// Unique, stable id (part of the Daily seed sequence; don't rename).
  String get id;

  RoundFamily get family;

  /// First round (0-based) where this type can appear.
  int get unlockRound => 0;

  /// Relative chance of being picked at [roundIndex]. Return 0 to skip.
  double weight(int roundIndex) => 1;

  /// Whether this type can run given the history so far (memory rounds need
  /// enough past rounds).
  bool isEligible(List<RoundRecord> history) => true;

  Round create(RoundContext ctx);
}
