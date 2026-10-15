import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../logic/difficulty.dart';
import '../logic/rng.dart';
import '../logic/run_engine.dart';
import '../rounds/round.dart';
import '../services/feedback.dart';
import '../services/storage.dart';
import 'arena_component.dart';

enum GamePhase { menu, playing, roundWon, fakeGameOver, gameOver }

/// Hidden options for the web link, for previews and screen recordings:
///   ?from=20   start Endless at round 20 (practice: scores aren't saved)
///   ?demo      the game plays itself (add &fail=15 to make it lose at 15)
///   ?retry     the first loss is always a surprise TRY AGAIN
class DemoConfig {
  const DemoConfig({this.startRound = 0, this.autoplay = false, this.failAt, this.forceRetry = false});

  factory DemoConfig.fromUri(Uri uri) {
    final q = uri.queryParameters;
    return DemoConfig(
      startRound: int.tryParse(q['from'] ?? '') ?? 0,
      autoplay: q.containsKey('demo'),
      failAt: int.tryParse(q['fail'] ?? ''),
      forceRetry: q.containsKey('retry'),
    );
  }

  final int startRound;
  final bool autoplay;
  final int? failAt;
  final bool forceRetry;

  bool get isActive => startRound > 0 || autoplay || forceRetry;
}

/// What the game-over screen shows (also used, unchanged, for the fake one).
class RunResult {
  const RunResult({
    required this.mode,
    required this.score,
    required this.reason,
    required this.best,
    required this.isNewBest,
    required this.date,
    this.dailyFirst,
    this.practice = false,
  });

  final GameMode mode;
  final int score;
  final String reason;
  final int best;
  final bool isNewBest;
  final DateTime date;

  /// For Daily runs: the first (official) score of the day.
  final int? dailyFirst;

  /// Practice/demo run from the hidden web options: nothing was saved.
  final bool practice;

  String get shareText {
    final rounds = score == 1 ? '1 round' : '$score rounds';
    if (mode == GameMode.daily) {
      return 'Button Panic Daily, ${prettyDate(date)}: I survived $rounds. '
          'Same buttons for everyone today. Can you beat me?';
    }
    return 'Button Panic Endless: I survived $rounds before the button got me.';
  }
}

String prettyDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// The Flame game: runs the loop, owns the current round and the chaos
/// layers, turns finger presses into round events, and shows the overlays.
class ButtonPanicGame extends FlameGame {
  ButtonPanicGame({required this.store, DateTime Function()? clock, this.demo = const DemoConfig()})
    : clock = clock ?? DateTime.now {
    audio.enabled = store.soundOn;
    haptics.enabled = store.hapticsOn;
  }

  final ScoreStore store;
  final DateTime Function() clock;
  final DemoConfig demo;
  final GameAudio audio = GameAudio();
  final GameHaptics haptics = GameHaptics();

  GamePhase phase = GamePhase.menu;
  RunEngine? engine;
  Round? round;
  ChaosState chaos = ChaosState.none;
  RunResult? lastResult;

  /// Banner across the top of the play area ("NEW: Liars", "TRY AGAIN").
  String banner = '';
  String bannerSub = '';
  double bannerTime = 0;
  bool bannerIsAlarm = false;

  /// Chaos state the arena reads when drawing.
  double rotation = 0;
  Offset shakeOffset = Offset.zero;
  double flashInvert = 0; // brief full-screen invert flash on the reveal

  double _phaseTimer = 0;
  final _shakeRng = math.Random();

  // Mid-round swap.
  double? _swapAt;
  (int, int)? _swapPair;
  double _swapProgress = -1;
  (double, double, double, double)? _swapFrom;

  final Map<int, String?> _pointerTargets = {};

  late final ArenaComponent arena;

  @override
  Color backgroundColor() => const Color(0xFF111117);

  @override
  Future<void> onLoad() async {
    arena = ArenaComponent();
    add(arena);
    await audio.preload();
    if (demo.autoplay) {
      Future.delayed(const Duration(milliseconds: 800), () => startRun(GameMode.endless));
    }
  }

  // ---------------------------------------------------------------------------
  // Run control
  // ---------------------------------------------------------------------------

  void startRun(GameMode mode) {
    final now = clock();
    final e = mode == GameMode.daily ? RunEngine.daily(now) : RunEngine.endless(math.Random().nextInt(1 << 30));
    // Practice/demo links only apply to Endless, so Daily stays fair.
    if (mode == GameMode.endless && demo.isActive) {
      e.skipTo(demo.startRound);
      if (demo.forceRetry) e.retryChance = 1;
    }
    engine = e;
    _demoCooldown = 0;
    _demoHolding = null;
    overlays.removeAll(['menu', 'gameOver']);
    phase = GamePhase.playing;
    banner = '';
    audio.startMusic();
    _beginRound();
  }

  void backToMenu() {
    audio.stopMusic();
    phase = GamePhase.menu;
    round = null;
    overlays.removeAll(['gameOver']);
    overlays.add('menu');
  }

  void _beginRound() {
    final e = engine!;
    final r = e.startRound();
    round = r;
    chaos = r.isCalm ? const ChaosState(calm: true, tempo: 0.8) : e.chaosFor(e.roundIndex);
    rotation = 0;
    _pointerTargets.clear();
    audio.setTempo(chaos.tempo);
    if (chaos.invert) haptics.chaos();

    // Plan a mid-round swap (deterministic per round).
    _swapAt = null;
    _swapPair = null;
    _swapProgress = -1;
    if (chaos.swap && r.allowSwap && r.buttons.length >= 2) {
      final rng = SeededRng.derive(e.seed, [e.roundIndex, 'swap']);
      final a = rng.nextInt(r.buttons.length);
      final b = (a + rng.range(1, r.buttons.length - 1)) % r.buttons.length;
      _swapPair = (a, b);
      _swapAt = r.timeLimit * rng.rangeDouble(0.3, 0.5);
    }

    final unlocked = e.familiesUnlockingAt(e.roundIndex);
    if (unlocked.isNotEmpty && e.retries == 0) {
      _showBanner('NEW: ${unlocked.map((f) => f.title).join(' + ')}', 'New round types unlocked', 1.6);
    } else if (r.isCalm && e.retries == 0) {
      _showBanner('...', '', 1.0);
    }
  }

  void _showBanner(String text, String sub, double seconds, {bool alarm = false}) {
    banner = text;
    bannerSub = sub;
    bannerTime = seconds;
    bannerIsAlarm = alarm;
  }

  // ---------------------------------------------------------------------------
  // Loop
  // ---------------------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    if (bannerTime > 0) bannerTime -= dt;
    if (flashInvert > 0) flashInvert -= dt;

    switch (phase) {
      case GamePhase.playing:
        _updatePlaying(dt);
      case GamePhase.roundWon:
        _phaseTimer -= dt;
        shakeOffset = Offset.zero;
        if (_phaseTimer <= 0) {
          phase = GamePhase.playing;
          _beginRound();
        }
      case GamePhase.fakeGameOver:
        _phaseTimer -= dt;
        if (_phaseTimer <= 0) _revealTryAgain();
      case GamePhase.menu:
      case GamePhase.gameOver:
        shakeOffset = Offset.zero;
    }
  }

  // Demo autoplay state.
  double _demoCooldown = 0;
  String? _demoHolding;

  bool get isPractice => engine?.mode == GameMode.endless && demo.isActive;

  void _updateDemo(Round r, double dt) {
    if (!demo.autoplay || r.verdict != Verdict.pending) return;
    if (demo.failAt != null && r.ctx.roundIndex >= demo.failAt!) {
      // Throw the run: press the button when it shouldn't be pressed.
      if (r.elapsed > 0.5 && r.demoMove() == null && r.buttons.isNotEmpty) {
        _demoTap(r, r.buttons.first.id);
      }
      return;
    }
    _demoCooldown -= dt;
    if (_demoCooldown > 0 || r.elapsed < 0.45) return;
    final move = r.demoMove();
    if (move == null) return;
    if (move.startsWith('hold:')) {
      final id = move.substring(5);
      _demoHolding = id;
      _setPressed(r, id, true);
      r.onPressDown(id);
    } else {
      _demoTap(r, move);
    }
    _demoCooldown = 0.2;
  }

  void _demoTap(Round r, String id) {
    _setPressed(r, id, true);
    audio.playTap();
    r.onPressDown(id);
    Future.delayed(const Duration(milliseconds: 90), () => _setPressed(r, id, false));
  }

  void _setPressed(Round r, String id, bool pressed) {
    for (final b in r.buttons) {
      if (b.id == id) b.pressed = pressed;
    }
  }

  void _updatePlaying(double dt) {
    final r = round;
    if (r == null) return;
    _updateDemo(r, dt);
    r.update(dt);
    if (r.verdict != Verdict.pending && _demoHolding != null) {
      _setPressed(r, _demoHolding!, false);
      _demoHolding = null;
    }
    _updateSwap(r, dt);

    // Chaos layers.
    rotation += chaos.rotationSpeed * dt;
    if (chaos.shake > 0) {
      final s = chaos.shake * 9;
      shakeOffset = Offset((_shakeRng.nextDouble() * 2 - 1) * s, (_shakeRng.nextDouble() * 2 - 1) * s);
    } else {
      shakeOffset = Offset.zero;
    }

    if (r.verdict == Verdict.success) {
      engine!.completeRound(r);
      audio.playSuccess();
      haptics.success();
      phase = GamePhase.roundWon;
      _phaseTimer = 0.3;
    } else if (r.verdict == Verdict.fail) {
      _handleLoss(r);
    }
  }

  void _updateSwap(Round r, double dt) {
    final at = _swapAt;
    final pair = _swapPair;
    if (at == null || pair == null) return;
    final buttons = r.buttons;
    if (_swapProgress < 0 && r.elapsed >= at) {
      final a = buttons[pair.$1];
      final b = buttons[pair.$2];
      _swapFrom = (a.x, a.y, b.x, b.y);
      _swapProgress = 0;
      haptics.chaos();
    }
    if (_swapProgress >= 0 && _swapProgress < 1) {
      _swapProgress = math.min(1, _swapProgress + dt / 0.22);
      final f = _swapFrom!;
      final e = _swapProgress * _swapProgress * (3 - 2 * _swapProgress);
      buttons[pair.$1]
        ..x = f.$1 + (f.$3 - f.$1) * e
        ..y = f.$2 + (f.$4 - f.$2) * e;
      buttons[pair.$2]
        ..x = f.$3 + (f.$1 - f.$3) * e
        ..y = f.$4 + (f.$2 - f.$4) * e;
    }
  }

  void _handleLoss(Round r) {
    final e = engine!;
    audio.playFail();
    haptics.fail();
    final outcome = e.registerLoss();
    if (demo.forceRetry) e.retryChance = Difficulty.retryChance; // only once
    if (outcome == LossOutcome.tryAgain) {
      // Show a game-over screen identical to the real one...
      lastResult = _buildResult(r, save: false);
      phase = GamePhase.fakeGameOver;
      _phaseTimer = Difficulty.fakeGameOverSeconds;
      overlays.add('gameOver');
    } else {
      phase = GamePhase.gameOver;
      lastResult = _buildResult(r, save: true);
      audio.stopMusic();
      overlays.add('gameOver');
    }
  }

  /// ...then reveal you're still alive, and the clock is already running.
  void _revealTryAgain() {
    overlays.remove('gameOver');
    audio.playReveal();
    haptics.chaos();
    flashInvert = 0.12;
    phase = GamePhase.playing;
    _beginRound();
    _showBanner('TRY AGAIN', 'Less time. The clock is running!', 1.3, alarm: true);
  }

  RunResult _buildResult(Round r, {required bool save}) {
    final e = engine!;
    final now = clock();
    final score = e.score;
    if (isPractice) save = false; // practice and demo runs never count
    if (e.mode == GameMode.daily) {
      final existing = store.dailyFor(now);
      final best = math.max(existing?.bestScore ?? 0, score);
      final isNewBest = existing != null && score > existing.bestScore;
      if (save) store.recordDaily(now, score);
      return RunResult(
        mode: e.mode,
        score: score,
        reason: r.failReason,
        best: best,
        isNewBest: isNewBest,
        date: now,
        dailyFirst: existing?.firstScore ?? score,
      );
    }
    final previous = store.bestEndless;
    if (save) store.recordEndless(score);
    return RunResult(
      mode: e.mode,
      score: score,
      reason: r.failReason,
      best: math.max(previous, score),
      isNewBest: score > previous && previous > 0 && !isPractice,
      date: now,
      practice: isPractice,
    );
  }

  // ---------------------------------------------------------------------------
  // Input (raw pointers, so holds and fast multi-taps are reliable)
  // ---------------------------------------------------------------------------

  void pointerDown(int pointer, Offset position) {
    final r = round;
    if (phase != GamePhase.playing || r == null || r.verdict != Verdict.pending) return;
    final target = arena.hitTest(position, r);
    _pointerTargets[pointer] = target;
    if (target != null) {
      for (final b in r.buttons) {
        if (b.id == target) {
          b.pressed = true;
          audio.playTap();
          haptics.tap();
        }
      }
    }
    r.onPressDown(target);
  }

  void pointerUp(int pointer) {
    if (!_pointerTargets.containsKey(pointer)) return;
    final target = _pointerTargets.remove(pointer);
    final r = round;
    if (r == null) return;
    for (final b in r.buttons) {
      if (b.id == target) b.pressed = false;
    }
    if (phase == GamePhase.playing && r.verdict == Verdict.pending) {
      r.onPressUp(target);
    }
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  void setSound(bool on) {
    audio.enabled = on;
    store.setSoundOn(on);
    if (!on) audio.stopMusic();
  }

  void setHaptics(bool on) {
    haptics.enabled = on;
    store.setHapticsOn(on);
  }

  @visibleForTesting
  void debugSetRound(Round r) => round = r;
}
