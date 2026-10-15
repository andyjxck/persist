import 'package:shared_preferences/shared_preferences.dart';

import '../logic/rng.dart';

/// Today's Daily result, kept on the device only.
class DailyResult {
  const DailyResult({required this.date, required this.firstScore, required this.bestScore});
  final String date;

  /// The first attempt of the day is the "official" one you share.
  final int firstScore;
  final int bestScore;
}

/// Stores best scores and the Daily result locally. No accounts, no servers.
class ScoreStore {
  ScoreStore(this._prefs);

  static Future<ScoreStore> open() async => ScoreStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _bestEndless = 'best_endless';
  static const _dailyDate = 'daily_date';
  static const _dailyFirst = 'daily_first';
  static const _dailyBest = 'daily_best';
  static const _soundOn = 'sound_on';
  static const _hapticsOn = 'haptics_on';

  int get bestEndless => _prefs.getInt(_bestEndless) ?? 0;

  /// Returns true if [score] is a new Endless best.
  Future<bool> recordEndless(int score) async {
    if (score > bestEndless) {
      await _prefs.setInt(_bestEndless, score);
      return true;
    }
    return false;
  }

  /// The stored Daily result if it is for [today], else null.
  DailyResult? dailyFor(DateTime today) {
    final key = dateKey(today);
    if (_prefs.getString(_dailyDate) != key) return null;
    return DailyResult(
      date: key,
      firstScore: _prefs.getInt(_dailyFirst) ?? 0,
      bestScore: _prefs.getInt(_dailyBest) ?? 0,
    );
  }

  /// Saves a Daily score. Returns the updated result.
  Future<DailyResult> recordDaily(DateTime today, int score) async {
    final existing = dailyFor(today);
    final key = dateKey(today);
    final result = DailyResult(
      date: key,
      firstScore: existing?.firstScore ?? score,
      bestScore: existing == null || score > existing.bestScore ? score : existing.bestScore,
    );
    await _prefs.setString(_dailyDate, key);
    await _prefs.setInt(_dailyFirst, result.firstScore);
    await _prefs.setInt(_dailyBest, result.bestScore);
    return result;
  }

  bool get soundOn => _prefs.getBool(_soundOn) ?? true;
  Future<void> setSoundOn(bool v) => _prefs.setBool(_soundOn, v);

  /// How many runs have been started on this device.
  int get runsPlayed => _prefs.getInt('runs_played') ?? 0;
  Future<void> countRun() => _prefs.setInt('runs_played', runsPlayed + 1);

  bool get hapticsOn => _prefs.getBool(_hapticsOn) ?? true;
  Future<void> setHapticsOn(bool v) => _prefs.setBool(_hapticsOn, v);
}
