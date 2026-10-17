import 'package:button_panic/services/leaderboard.dart';

/// A leaderboard server in memory, for tests.
class FakeLeaderboardApi implements LeaderboardApi {
  FakeLeaderboardApi({this.rank = 1, this.startError, this.submitError, this.topError, List<LeaderboardEntry>? rows}) : rows = rows ?? defaultRows;

  int rank;
  String? startError;
  String? submitError;
  String? topError;
  List<LeaderboardEntry> rows;

  final List<String> started = [];
  final List<(String, String, String, int)> submitted = [];
  final List<String> renamed = [];
  int topCalls = 0;
  int _runs = 0;

  static final defaultRows = [
    for (var i = 1; i <= 20; i++) LeaderboardEntry(rank: i, name: i == 7 ? 'ANDREW' : (i.isEven ? 'NIGHTSHIFT$i' : 'P$i'), score: 200 - i * 7, me: i == 7),
  ];

  @override
  Future<String> startRun({required String player, required String board}) async {
    started.add(board);
    if (startError != null) throw LeaderboardException(startError!);
    return 'run-${++_runs}';
  }

  @override
  Future<int> submit({required String run, required String player, required String name, required int score}) async {
    if (submitError != null) throw LeaderboardException(submitError!);
    submitted.add((run, player, name, score));
    return rank;
  }

  @override
  Future<List<LeaderboardEntry>> top({required String board, required String player, int limit = 20}) async {
    topCalls++;
    if (topError != null) throw LeaderboardException(topError!);
    return rows.take(limit).toList();
  }

  @override
  Future<String> rename({required String player, required String name}) async {
    renamed.add(name);
    return name;
  }
}
