import 'layout.dart';
import 'round.dart';

// ---------------------------------------------------------------------------
// "Remember this" rounds.
//
// A Remember round flashes something (a number or a word) and asks you to
// press the button. A few rounds later, with other chaos in between, a Recall
// round asks what it was. Only one memo is ever outstanding at a time.
// ---------------------------------------------------------------------------

const rememberTypeId = 'remember_this';
const recallTypeId = 'recall_this';

/// Words chosen to be short, concrete and never a colour name (colour words
/// would switch off the screen invert and muddle the liar rounds).
const memoWords = [
  'FROG', 'LAMP', 'SOCK', 'PEAR', 'KITE', 'MOON', 'DUCK', 'FORK',
  'BOAT', 'CAKE', 'WOLF', 'HARP', 'DRUM', 'SHOE', 'BELL', 'NEST',
];

/// Round index of the memo still waiting to be asked about, or null.
/// Works on type ids alone, so the engine can decide eligibility without
/// knowing what the memo was.
int? outstandingMemoAt(List<RoundRecord> history) {
  for (var i = history.length - 1; i >= 0; i--) {
    final id = history[i].typeId;
    if (id == recallTypeId) return null;
    if (id == rememberTypeId) return i;
  }
  return null;
}

/// Rounds that must pass between a memo and the question about it.
const _minGap = 2;

class RememberType extends RoundType {
  const RememberType();
  @override
  String get id => rememberTypeId;
  @override
  RoundFamily get family => RoundFamily.memory;
  @override
  int get unlockRound => 8;
  @override
  double weight(int roundIndex) => 0.9;
  @override
  bool isEligible(List<RoundRecord> history) => outstandingMemoAt(history) == null;
  @override
  Round create(RoundContext ctx) => RememberRound(ctx);
}

class RememberRound extends Round {
  RememberRound(super.ctx) {
    final rng = ctx.rng;
    isNumber = rng.chance(0.5);
    memo = isNumber ? '${rng.range(12, 98)}' : rng.pick(memoWords);
    final spot = randomSpot(rng);
    button = GameButton(id: 'main', colour: rng.pick(GameColour.all), label: memo, x: spot.$1, y: spot.$2);
  }

  late final bool isNumber;
  late final String memo;
  late final GameButton button;

  @override
  String get instruction => 'Remember: $memo';
  @override
  String get hint => 'Now press the button';
  @override
  List<GameButton> get buttons => [button];
  @override
  double get baseTime => 3.2;
  @override
  String? get memoToKeep => '${isNumber ? 'n' : 'w'}:$memo';
  @override
  String? demoMove() => 'main';

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') succeed();
  }
}

class RecallType extends RoundType {
  const RecallType();
  @override
  String get id => recallTypeId;
  @override
  RoundFamily get family => RoundFamily.memory;
  @override
  int get unlockRound => 10;
  @override
  double weight(int roundIndex) => 3.5;
  @override
  bool isEligible(List<RoundRecord> history) {
    final at = outstandingMemoAt(history);
    return at != null && history.length - at > _minGap;
  }

  @override
  Round create(RoundContext ctx) => RecallRound(ctx);
}

class RecallRound extends Round {
  RecallRound(super.ctx) {
    final rng = ctx.rng;
    final at = outstandingMemoAt(ctx.history);
    final stored = at == null ? null : ctx.history[at].memo;
    if (stored != null && stored.length > 2) {
      isNumber = stored.startsWith('n:');
      answer = stored.substring(2);
    } else {
      // Never happens in a real run (the type is only picked when a memo is
      // waiting); keeps the round valid if built directly.
      isNumber = true;
      answer = '${rng.range(12, 98)}';
    }

    final count = ctx.difficulty > 0.6 ? 4 : 3;
    final options = <String>[answer, ...decoysFor(answer, isNumber, count - 1, rng.shuffled)];
    final colours = rng.shuffled(GameColour.all).take(count).toList();
    final order = rng.shuffled([for (var i = 0; i < count; i++) i]);
    _buttons = [
      for (var i = 0; i < count; i++) GameButton(id: 'r$i', colour: colours[i], label: options[order[i]]),
    ];
    placeInSlots(_buttons, rng);
  }

  late final bool isNumber;
  late final String answer;
  late final List<GameButton> _buttons;

  GameButton get correct => _buttons.firstWhere((b) => b.label == answer);

  @override
  String get instruction => isNumber ? 'What NUMBER did you have to remember?' : 'What WORD did you have to remember?';
  @override
  List<GameButton> get buttons => _buttons;
  @override
  double get baseTime => 3.6;
  @override
  GameColour get rememberedColour => correct.colour;
  @override
  String? demoMove() => correct.id;

  @override
  void onPressDown(String? targetId) {
    if (targetId == null) return;
    final b = _buttons.where((b) => b.id == targetId);
    if (b.isEmpty) return;
    if (b.first.label == answer) {
      succeed();
    } else {
      fail('It was $answer.');
    }
  }

  @override
  void onTimeout() => fail('Too slow. It was $answer.');
}

/// Wrong answers that look like the right one: for numbers, the digits
/// swapped and near neighbours; for words, other memo words.
List<String> decoysFor(String answer, bool isNumber, int count, List<String> Function(Iterable<String>) shuffle) {
  final pool = <String>{};
  if (isNumber) {
    final n = int.parse(answer);
    final swapped = answer.split('').reversed.join();
    final candidates = [swapped, '${n + 1}', '${n - 1}', '${n + 10}', '${n - 10}', '${n + 11}', '${n - 9}'];
    for (final c in shuffle(candidates)) {
      final v = int.tryParse(c);
      if (v == null || v < 10 || v > 99 || c == answer || c.startsWith('0')) continue;
      pool.add(c);
    }
  } else {
    for (final w in shuffle(memoWords)) {
      if (w != answer) pool.add(w);
    }
  }
  return pool.take(count).toList();
}
