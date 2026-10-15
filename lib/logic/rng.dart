/// A tiny deterministic random number generator (mulberry32).
///
/// We don't use `dart:math`'s `Random(seed)` because its sequence is not
/// guaranteed to be the same on every platform (mobile vs web). The Daily run
/// must give *everyone* the same rounds, so all arithmetic here is kept inside
/// 32 bits and produces identical numbers on iOS, Android and the web.
class SeededRng {
  SeededRng(int seed) : _state = seed & 0xffffffff;

  /// Builds a generator from a seed plus any number of extra parts, e.g.
  /// `SeededRng.derive(runSeed, [roundIndex, 'chaos'])`. Each combination gives
  /// an independent stream, so one round's randomness never shifts another's.
  factory SeededRng.derive(int seed, List<Object> parts) {
    var h = seed & 0xffffffff;
    for (final p in parts) {
      h = hashString('$h|$p');
    }
    return SeededRng(h);
  }

  int _state;

  /// Next 32-bit unsigned integer.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xffffffff;
    var t = imul32(_state ^ (_state >>> 15), 1 | _state);
    t = ((t + imul32(t ^ (t >>> 7), 61 | t)) & 0xffffffff) ^ t;
    t &= 0xffffffff;
    return (t ^ (t >>> 14)) & 0xffffffff;
  }

  /// A double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// An int in [0, max).
  int nextInt(int max) {
    assert(max > 0);
    return (nextDouble() * max).floor();
  }

  /// An int in [min, max] (both inclusive).
  int range(int min, int max) => min + nextInt(max - min + 1);

  /// A double in [min, max).
  double rangeDouble(double min, double max) => min + nextDouble() * (max - min);

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// Returns a shuffled copy (Fisher-Yates).
  List<T> shuffled<T>(Iterable<T> items) {
    final list = List<T>.of(items);
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}

/// 32-bit integer multiply that behaves the same on the Dart VM and on the web.
int imul32(int a, int b) {
  final ah = (a >>> 16) & 0xffff;
  final al = a & 0xffff;
  final bh = (b >>> 16) & 0xffff;
  final bl = b & 0xffff;
  final high = ((ah * bl + al * bh) & 0xffff) << 16;
  return (al * bl + high) & 0xffffffff;
}

/// FNV-1a hash of a string, as an unsigned 32-bit int.
int hashString(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = imul32(h, 0x01000193);
  }
  return h & 0xffffffff;
}

/// The seed for the Daily run: the same for everyone on the same calendar day.
int dailySeed(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return hashString('button-panic-daily-$y-$m-$d');
}

String dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
