import 'dart:convert';

import 'package:button_panic/logic/rng.dart';
import 'package:button_panic/logic/run_engine.dart';
import 'package:button_panic/services/leaderboard.dart';
import 'package:button_panic/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_leaderboard.dart';

// The leaderboard client: switched off unless the build is given a Supabase
// project, talks to the four bp_* functions with the right headers, turns
// server refusals into messages, and keeps a score until you pick a name.

Future<ScoreStore> _store([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'sound_on': false, 'haptics_on': false, ...prefs});
  return ScoreStore.open();
}

void main() {
  group('switched off unless built with a project', () {
    test('this build (no --dart-define) has no project, so the boards are off', () async {
      expect(LeaderboardConfig.fromEnvironment.enabled, isFalse);
      final lb = Leaderboards.forBuild(await _store());
      expect(lb.enabled, isFalse);
      expect(lb.api, isNull);
    });

    test('a project needs an https URL and a key', () async {
      expect(const LeaderboardConfig(url: '', key: '').enabled, isFalse);
      expect(const LeaderboardConfig(url: 'https://x.supabase.co', key: '').enabled, isFalse);
      expect(const LeaderboardConfig(url: 'http://x.supabase.co', key: 'k').enabled, isFalse);
      expect(const LeaderboardConfig(url: 'https://x.supabase.co', key: 'sb_publishable_k').enabled, isTrue);
      final lb = Leaderboards.forBuild(
        await _store(),
        config: const LeaderboardConfig(url: 'https://x.supabase.co', key: 'sb_publishable_k'),
      );
      expect(lb.enabled, isTrue);
      expect(lb.api, isA<SupabaseLeaderboardApi>());
    });

    test('switched off: starting and ending a run sends nothing and asks for nothing', () async {
      final lb = Leaderboards(store: await _store());
      lb.runStarted('endless:phone');
      lb.runEnded(40);
      expect(lb.status, SubmitStatus.none);
      expect(lb.pendingScore, isNull);
      await lb.load('endless:phone');
      expect(lb.entries('endless:phone'), isNull);
      expect(lb.isLoading('endless:phone'), isFalse);
    });
  });

  group('Supabase client', () {
    late List<http.Request> sent;
    SupabaseLeaderboardApi api(String key, Future<http.Response> Function(http.Request r) reply, {String url = 'https://abc.supabase.co/'}) {
      sent = [];
      return SupabaseLeaderboardApi(
        LeaderboardConfig(url: url, key: key),
        client: MockClient((r) {
          sent.add(r);
          return reply(r);
        }),
      );
    }

    test('calls the bp_* functions over POST with the key, and no bearer for publishable keys', () async {
      final a = api('sb_publishable_abc', (r) async => http.Response(jsonEncode('run-1'), 200));
      expect(await a.startRun(player: 'p1', board: 'endless:phone'), 'run-1');
      final r = sent.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://abc.supabase.co/rest/v1/rpc/bp_start_run');
      expect(r.headers['apikey'], 'sb_publishable_abc');
      expect(r.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(r.body), {'p_player': 'p1', 'p_board': 'endless:phone'});
    });

    test('old-style JWT anon keys also go in Authorization', () async {
      final a = api('eyJhbGciOi.test', (r) async => http.Response(jsonEncode('ANDREW'), 200));
      expect(await a.rename(player: 'p1', name: 'andrew'), 'ANDREW');
      expect(sent.single.headers['Authorization'], 'Bearer eyJhbGciOi.test');
      expect(sent.single.url.path, '/rest/v1/rpc/bp_rename');
      expect(jsonDecode(sent.single.body), {'p_player': 'p1', 'p_name': 'andrew'});
    });

    test('submit returns the rank, and top reads rows including your own', () async {
      final a = api('k', (r) async {
        if (r.url.path.endsWith('bp_submit')) {
          return http.Response(
            jsonEncode([
              {'rank': 4},
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode([
            {'rank': 1, 'name': 'ZED', 'score': 90, 'me': false},
            {'rank': 2, 'name': 'ANDREW', 'score': 80, 'me': true},
          ]),
          200,
        );
      });
      expect(await a.submit(run: 'r', player: 'p', name: 'ANDREW', score: 80), 4);
      expect(jsonDecode(sent.last.body), {'p_run': 'r', 'p_player': 'p', 'p_name': 'ANDREW', 'p_score': 80});
      final rows = await a.top(board: 'daily:phone:2026-10-17', player: 'p', limit: 5);
      expect(jsonDecode(sent.last.body), {'p_board': 'daily:phone:2026-10-17', 'p_player': 'p', 'p_limit': 5});
      expect(rows.map((e) => (e.rank, e.name, e.score, e.me)).toList(), [(1, 'ZED', 90, false), (2, 'ANDREW', 80, true)]);
    });

    test('server refusals keep their code; unknown errors are refused; 5xx and no connection are offline', () async {
      Future<String> codeFor(Future<http.Response> Function(http.Request) reply) async {
        try {
          await api('k', reply).startRun(player: 'p', board: 'b');
        } on LeaderboardException catch (e) {
          return e.code;
        }
        return 'no error';
      }

      expect(await codeFor((_) async => http.Response(jsonEncode({'message': 'bp_name_blocked'}), 400)), 'bp_name_blocked');
      expect(await codeFor((_) async => http.Response(jsonEncode({'message': 'bp_too_fast'}), 400)), 'bp_too_fast');
      expect(await codeFor((_) async => http.Response(jsonEncode({'message': 'permission denied'}), 401)), 'refused');
      expect(await codeFor((_) async => http.Response('not json', 400)), 'refused');
      expect(await codeFor((_) async => http.Response('', 503)), 'offline');
      expect(await codeFor((_) async => throw http.ClientException('no network')), 'offline');
      // A start that doesn't return an id is refused, not trusted.
      expect(await codeFor((_) async => http.Response(jsonEncode(null), 200)), 'refused');
    });

    test('every refusal code has a message for the player', () {
      for (final code in [
        'bp_name_invalid',
        'bp_name_blocked',
        'bp_too_fast',
        'bp_slow_down',
        'bp_used_run',
        'bp_bad_run',
        'bp_stale_run',
        'offline',
        'refused',
      ]) {
        expect(LeaderboardException(code).message, isNotEmpty, reason: code);
      }
      expect(const LeaderboardException('bp_used_run').message, const LeaderboardException('bp_stale_run').message);
    });
  });

  group('boards and names', () {
    test('board names match the server: one per version, a Daily per day, nothing for Story', () {
      final d = DateTime(2026, 10, 17, 23, 30);
      expect(Boards.forRun(GameMode.daily, '', d), 'daily:phone:${dateKey(d)}');
      expect(Boards.forRun(GameMode.daily, 'desktop', d), 'daily:desktop:${dateKey(d)}');
      expect(Boards.forRun(GameMode.endless, 'mouse', d), 'endless:mouse');
      expect(Boards.forRun(GameMode.story, '', d), isNull);
    });

    test('name rules: 2 to 14 letters or numbers, tidied, with rude words blocked even when disguised', () {
      expect(NameRules.problem('Andrew'), isNull);
      expect(NameRules.problem('  silver   tongue '), isNull);
      expect(NameRules.tidy('  silver   tongue '), 'silver tongue');
      expect(NameRules.problem('A'), isNotNull);
      expect(NameRules.problem('ABCDEFGHIJKLMNO'), isNotNull);
      expect(NameRules.problem('___'), isNotNull);
      expect(NameRules.problem('bad<name>'), isNotNull);
      expect(NameRules.problem('sh1t'), const LeaderboardException('bp_name_blocked').message);
      expect(NameRules.problem('shiiiit'), const LeaderboardException('bp_name_blocked').message);
      expect(NameRules.problem('cock'), isNotNull);
      // Whole-word checks don't catch ordinary names.
      expect(NameRules.problem('Cassie'), isNull);
      expect(NameRules.problem('Scunthorpe'), isNotNull, reason: 'the inside list is strict by design');
    });
  });

  group('sending a score', () {
    test('first time: the score waits for a name, then goes with it and shows the rank', () async {
      final api = FakeLeaderboardApi(rank: 3);
      final lb = Leaderboards(store: await _store(), api: api);
      expect(lb.enabled, isTrue);
      lb.runStarted('endless:phone');
      expect(api.started, ['endless:phone']);
      lb.runEnded(42);
      expect(lb.status, SubmitStatus.needsName);
      expect(lb.pendingScore, 42);
      expect(api.submitted, isEmpty);
      expect(await lb.setName('sh1t'), isNotNull);
      expect(lb.status, SubmitStatus.needsName);
      expect(await lb.setName(' Andrew '), isNull);
      expect(lb.name, 'Andrew');
      expect(lb.status, SubmitStatus.sent);
      expect(lb.lastRank, 3);
      expect(api.submitted.single, ('run-1', lb.playerId, 'Andrew', 42));
    });

    test('with a name already saved, the score goes straight away', () async {
      final api = FakeLeaderboardApi(rank: 1);
      final lb = Leaderboards(store: await _store({'lb_name': 'ANDREW'}), api: api);
      lb.runStarted('daily:phone:2026-10-17');
      lb.runEnded(12);
      await pumpEventQueue();
      expect(lb.status, SubmitStatus.sent);
      expect(api.submitted.single.$4, 12);
    });

    test('a name the server refuses can be fixed; any other refusal is final', () async {
      final api = FakeLeaderboardApi(submitError: 'bp_name_blocked');
      final lb = Leaderboards(store: await _store({'lb_name': 'ANDREW'}), api: api);
      lb.runStarted('endless:phone');
      lb.runEnded(5);
      await pumpEventQueue();
      expect(lb.status, SubmitStatus.needsName);
      expect(lb.error, const LeaderboardException('bp_name_blocked').message);

      api.submitError = 'bp_too_fast';
      lb.runStarted('endless:phone');
      lb.runEnded(5);
      await pumpEventQueue();
      expect(lb.status, SubmitStatus.failed);
    });

    test('a run that could not get an id from the server fails as offline', () async {
      final api = FakeLeaderboardApi(startError: 'offline');
      final lb = Leaderboards(store: await _store({'lb_name': 'ANDREW'}), api: api);
      lb.runStarted('endless:phone');
      lb.runEnded(5);
      await pumpEventQueue();
      expect(lb.status, SubmitStatus.failed);
      expect(lb.error, const LeaderboardException('offline').message);
      expect(api.submitted, isEmpty);
    });

    test('an abandoned run sends nothing, and the player id is made once and kept', () async {
      final store = await _store();
      final api = FakeLeaderboardApi();
      final lb = Leaderboards(store: store, api: api);
      lb.runStarted('endless:phone');
      lb.runAbandoned();
      lb.runEnded(9);
      expect(lb.status, SubmitStatus.none);
      final id = lb.playerId;
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(Leaderboards(store: store, api: api).playerId, id);
    });

    test('boards are cached for 20 seconds, and a rename clears the cache', () async {
      final api = FakeLeaderboardApi();
      final lb = Leaderboards(store: await _store({'lb_name': 'ANDREW'}), api: api);
      var now = DateTime(2026, 10, 17, 15);
      await lb.load('endless:phone', clock: () => now);
      await lb.load('endless:phone', clock: () => now);
      expect(api.topCalls, 1);
      now = now.add(const Duration(seconds: 21));
      await lb.load('endless:phone', clock: () => now);
      expect(api.topCalls, 2);
      expect(lb.entries('endless:phone'), isNotEmpty);
      expect(await lb.setName('Andy'), isNull);
      expect(api.renamed, ['Andy']);
      expect(lb.entries('endless:phone'), isNull);
    });

    test('a board that fails to load says why', () async {
      final api = FakeLeaderboardApi(topError: 'offline');
      final lb = Leaderboards(store: await _store(), api: api);
      await lb.load('endless:phone');
      expect(lb.loadError('endless:phone'), const LeaderboardException('offline').message);
      expect(lb.entries('endless:phone'), isNull);
    });
  });
}
