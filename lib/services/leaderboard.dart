import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../logic/rng.dart';
import '../logic/run_engine.dart';
import 'storage.dart';

/// Where the leaderboards live. Both values are public by design (a
/// Supabase project URL and its publishable / anon key): the database only
/// lets that key call the four bp_* functions in supabase/leaderboard.sql.
///
/// Set at build time:
///   flutter build web --dart-define=BP_SUPABASE_URL=https://xyz.supabase.co \
///                     --dart-define=BP_SUPABASE_KEY=sb_publishable_...
/// Without them the leaderboards are switched off and never shown.
class LeaderboardConfig {
  const LeaderboardConfig({required this.url, required this.key});

  static const fromEnvironment = LeaderboardConfig(
    url: String.fromEnvironment('BP_SUPABASE_URL'),
    key: String.fromEnvironment('BP_SUPABASE_KEY'),
  );

  final String url;
  final String key;

  bool get enabled => url.startsWith('https://') && key.isNotEmpty;
}

/// One row of a board.
class LeaderboardEntry {
  const LeaderboardEntry({required this.rank, required this.name, required this.score, this.me = false});
  final int rank;
  final String name;
  final int score;

  /// This device's own row.
  final bool me;
}

/// A refusal from the server, by its code (see leaderboard.sql).
class LeaderboardException implements Exception {
  const LeaderboardException(this.code);
  final String code;

  /// What to tell the player.
  String get message => switch (code) {
    'bp_name_invalid' => 'Use 2 to 14 letters or numbers.',
    'bp_name_blocked' => 'Pick a different name.',
    'bp_too_fast' => 'That score came in too fast to count.',
    'bp_slow_down' => 'Too many runs at once. Try again in a minute.',
    'bp_used_run' || 'bp_bad_run' || 'bp_stale_run' => 'That run can\'t be sent any more.',
    'offline' => 'Can\'t reach the boards right now.',
    _ => 'The boards refused that score.',
  };

  @override
  String toString() => 'LeaderboardException($code)';
}

/// The calls the game makes. One real version (Supabase over HTTPS); tests
/// use a fake.
abstract class LeaderboardApi {
  Future<String> startRun({required String player, required String board});
  Future<int> submit({required String run, required String player, required String name, required int score});
  Future<List<LeaderboardEntry>> top({required String board, required String player, int limit = 20});
  Future<String> rename({required String player, required String name});
}

/// Calls the bp_* database functions through Supabase's REST endpoint.
class SupabaseLeaderboardApi implements LeaderboardApi {
  SupabaseLeaderboardApi(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final LeaderboardConfig config;
  final http.Client _client;

  static const _timeout = Duration(seconds: 8);

  Future<Object?> _rpc(String fn, Map<String, Object?> args) async {
    final uri = Uri.parse('${config.url.replaceAll(RegExp(r'/+$'), '')}/rest/v1/rpc/$fn');
    final headers = {
      'apikey': config.key,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // Old-style anon keys are JWTs and go in Authorization too; the newer
      // publishable keys only go in apikey.
      if (config.key.startsWith('eyJ')) 'Authorization': 'Bearer ${config.key}',
    };
    final http.Response res;
    try {
      res = await _client.post(uri, headers: headers, body: jsonEncode(args)).timeout(_timeout);
    } catch (_) {
      throw const LeaderboardException('offline');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body.isEmpty ? null : jsonDecode(res.body);
    }
    var code = 'refused';
    try {
      final body = jsonDecode(res.body);
      final m = body is Map ? body['message'] : null;
      if (m is String && m.startsWith('bp_')) code = m;
    } catch (_) {}
    if (res.statusCode >= 500 && code == 'refused') code = 'offline';
    throw LeaderboardException(code);
  }

  @override
  Future<String> startRun({required String player, required String board}) async {
    final id = await _rpc('bp_start_run', {'p_player': player, 'p_board': board});
    if (id is! String) throw const LeaderboardException('refused');
    return id;
  }

  @override
  Future<int> submit({required String run, required String player, required String name, required int score}) async {
    final rows = await _rpc('bp_submit', {'p_run': run, 'p_player': player, 'p_name': name, 'p_score': score});
    if (rows is List && rows.isNotEmpty && rows.first is Map) {
      return ((rows.first as Map)['rank'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  @override
  Future<List<LeaderboardEntry>> top({required String board, required String player, int limit = 20}) async {
    final rows = await _rpc('bp_top', {'p_board': board, 'p_player': player, 'p_limit': limit});
    if (rows is! List) return const [];
    return [
      for (final r in rows.whereType<Map>())
        LeaderboardEntry(
          rank: (r['rank'] as num?)?.toInt() ?? 0,
          name: '${r['name'] ?? ''}',
          score: (r['score'] as num?)?.toInt() ?? 0,
          me: r['me'] == true,
        ),
    ];
  }

  @override
  Future<String> rename({required String player, required String name}) async {
    final clean = await _rpc('bp_rename', {'p_player': player, 'p_name': name});
    return clean is String ? clean : name;
  }
}

/// Board names, matching the server's checks.
class Boards {
  /// '' (the phone version), 'mouse' or 'desktop' -> the board's version tag.
  static String version(String variant) => variant.isEmpty ? 'phone' : variant;

  static String daily(String variant, DateTime date) => 'daily:${version(variant)}:${dateKey(date)}';
  static String endless(String variant) => 'endless:${version(variant)}';

  static String? forRun(GameMode mode, String variant, DateTime date) => switch (mode) {
    GameMode.daily => daily(variant, date),
    GameMode.endless => endless(variant),
    GameMode.story => null,
  };
}

/// The same name rules the server applies, so most problems show up before
/// anything is sent. The server has the final say (and the full word list).
class NameRules {
  static final _allowed = RegExp(r'^[A-Za-z0-9 _.\-]{2,14}$');

  /// A short list for instant feedback; the full list lives in the database.
  static const _inside = [
    'fuck', 'fck', 'shit', 'cunt', 'nigg', 'niga', 'faggot', 'rapist', 'nazi', 'hitler', 'wank', 'twat', //
    'bitch', 'whore', 'slut', 'pussy', 'retard', 'spastic', 'kike', 'chink', 'tranny', 'porn', 'penis', //
    'paedo', 'bollock', 'bellend', 'nonce', 'asshole', 'bastard',
  ];
  static const _whole = ['ass', 'arse', 'cum', 'fag', 'tit', 'tits', 'nig', 'coon', 'sex', 'cock', 'dick', 'rape', 'pedo', 'paki'];

  static String tidy(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Null if [name] looks fine, else what's wrong with it.
  static String? problem(String name) {
    final n = tidy(name);
    if (!_allowed.hasMatch(n) || !RegExp(r'[A-Za-z0-9]').hasMatch(n)) {
      return const LeaderboardException('bp_name_invalid').message;
    }
    const from = '0134578', to = 'oieastb';
    final mapped = String.fromCharCodes(
      n.toLowerCase().codeUnits.map((c) {
        final i = from.codeUnits.indexOf(c);
        return i < 0 ? c : to.codeUnitAt(i);
      }),
    );
    final tokens = mapped.split(RegExp('[^a-z]+'));
    final flat = mapped.replaceAll(RegExp('[^a-z]'), '');
    final squeezed = flat.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
    final blocked =
        _inside.any((w) => flat.contains(w) || squeezed.contains(w)) ||
        _whole.any((w) => tokens.contains(w) || flat == w || squeezed == w);
    return blocked ? const LeaderboardException('bp_name_blocked').message : null;
  }
}

/// Where the result screen's score is with the boards.
enum SubmitStatus {
  /// Nothing to send (leaderboards off, practice, story).
  none,

  /// A score is waiting for you to pick a name.
  needsName,
  sending,
  sent,
  failed,
}

/// The game's side of the leaderboards: this device's id and name, the run
/// in progress, and the boards it has loaded.
class Leaderboards extends ChangeNotifier {
  Leaderboards({required this.store, this.api, math.Random? random}) : _random = random ?? _secureOrDefault();

  /// Leaderboards for a build: on when the build was given a project.
  factory Leaderboards.forBuild(ScoreStore store, {LeaderboardConfig config = LeaderboardConfig.fromEnvironment}) =>
      Leaderboards(store: store, api: config.enabled ? SupabaseLeaderboardApi(config) : null);

  static math.Random _secureOrDefault() {
    try {
      return math.Random.secure();
    } catch (_) {
      return math.Random();
    }
  }

  final ScoreStore store;
  final LeaderboardApi? api;
  final math.Random _random;

  bool get enabled => api != null;

  String get name => store.playerName;
  bool get hasName => name.isNotEmpty;

  /// This device's id, made the first time it's needed.
  String get playerId {
    var id = store.playerId;
    if (id.isEmpty) {
      id = _uuidV4();
      store.setPlayerId(id);
    }
    return id;
  }

  String _uuidV4() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ---------------------------------------------------------------------------
  // The run in progress
  // ---------------------------------------------------------------------------

  String? _runBoard;
  Future<String?>? _runId;

  /// The last finished run's board and score, while it's being sent or
  /// waiting for a name.
  String? pendingBoard;
  int? pendingScore;
  Future<String?>? _pendingRun;

  SubmitStatus status = SubmitStatus.none;

  /// Where the last sent score ranks on its board.
  int? lastRank;

  /// What went wrong with the last send, for the player.
  String? error;

  /// Call when a run that counts starts. Asks the server for a run id in the
  /// background; the game never waits for it.
  void runStarted(String board) {
    if (!enabled) return;
    _runBoard = board;
    final f = api!.startRun(player: playerId, board: board).then<String?>((id) => id).catchError((Object _) => null);
    _runId = f;
  }

  /// Call when that run is over. Sends the score if you have a name; else
  /// keeps it until you pick one.
  void runEnded(int score) {
    final board = _runBoard;
    final run = _runId;
    _runBoard = null;
    _runId = null;
    if (!enabled || board == null || run == null) {
      status = SubmitStatus.none;
      notifyListeners();
      return;
    }
    pendingBoard = board;
    pendingScore = score;
    _pendingRun = run;
    lastRank = null;
    error = null;
    if (hasName) {
      _send();
    } else {
      status = SubmitStatus.needsName;
      notifyListeners();
    }
  }

  /// A run that was abandoned (back to the menu) sends nothing.
  void runAbandoned() {
    _runBoard = null;
    _runId = null;
  }

  /// Clears the result screen's state (a new run, or back to the menu).
  void clearPending() {
    pendingBoard = null;
    pendingScore = null;
    _pendingRun = null;
    status = SubmitStatus.none;
    error = null;
    lastRank = null;
    notifyListeners();
  }

  Future<void> _send() async {
    final board = pendingBoard, score = pendingScore, run = _pendingRun;
    if (board == null || score == null || run == null) return;
    status = SubmitStatus.sending;
    notifyListeners();
    try {
      final id = await run;
      if (id == null) throw const LeaderboardException('offline');
      final rank = await api!.submit(run: id, player: playerId, name: name, score: score);
      if (pendingBoard != board) return; // moved on meanwhile
      lastRank = rank;
      status = SubmitStatus.sent;
      _cache.remove(board);
    } on LeaderboardException catch (e) {
      if (pendingBoard != board) return;
      error = e.message;
      // A refused name can be fixed and sent again; anything else can't.
      status = e.code.startsWith('bp_name') ? SubmitStatus.needsName : SubmitStatus.failed;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Name
  // ---------------------------------------------------------------------------

  /// Saves [raw] as your name (after the local check) and sends any score
  /// waiting for it. Returns what's wrong with the name, or null.
  Future<String?> setName(String raw) async {
    final n = NameRules.tidy(raw);
    final problem = NameRules.problem(n);
    if (problem != null) return problem;
    final had = hasName;
    await store.setPlayerName(n);
    error = null;
    notifyListeners();
    if (status == SubmitStatus.needsName) {
      await _send();
      if (status == SubmitStatus.needsName) return error;
    } else if (had && enabled) {
      try {
        await api!.rename(player: playerId, name: n);
        _cache.clear();
      } on LeaderboardException catch (e) {
        return e.message;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Reading boards
  // ---------------------------------------------------------------------------

  final Map<String, List<LeaderboardEntry>> _cache = {};
  final Map<String, DateTime> _loadedAt = {};
  final Set<String> _loading = {};
  final Map<String, String> _loadErrors = {};

  List<LeaderboardEntry>? entries(String board) => _cache[board];
  bool isLoading(String board) => _loading.contains(board);
  String? loadError(String board) => _loadErrors[board];

  /// Fetches [board] unless it was fetched in the last 20 seconds.
  Future<void> load(String board, {bool force = false, DateTime Function() clock = DateTime.now}) async {
    if (!enabled || _loading.contains(board)) return;
    final at = _loadedAt[board];
    if (!force && at != null && clock().difference(at) < const Duration(seconds: 20) && _cache.containsKey(board)) return;
    _loading.add(board);
    _loadErrors.remove(board);
    notifyListeners();
    try {
      _cache[board] = await api!.top(board: board, player: playerId);
      _loadedAt[board] = clock();
    } on LeaderboardException catch (e) {
      _loadErrors[board] = e.message;
    } catch (_) {
      _loadErrors[board] = const LeaderboardException('offline').message;
    }
    _loading.remove(board);
    notifyListeners();
  }
}
