import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../logic/clock_beat.dart';
import '../logic/soundtrack.dart';
import '../logic/difficulty.dart';
import '../logic/rng.dart';
import '../logic/run_engine.dart';
import '../rounds/round.dart';
import '../services/feedback.dart';
import '../services/storage.dart';
import '../ui/theme.dart';
import 'arena_component.dart';

enum GamePhase { menu, playing, roundWon, failing, fakeGameOver, gameOver }

/// Hidden options for the web link, for previews and screen recordings:
///   ?from=20   start Endless at round 20 (practice: scores aren't saved)
///   ?demo      the game plays itself (add &fail=15 to make it lose at 15)
///   ?retry     the first loss is always a surprise TRY AGAIN
///   ?seed=123  Endless uses this seed (repeatable previews)
class DemoConfig {
  const DemoConfig({this.startRound = 0, this.autoplay = false, this.failAt, this.forceRetry = false, this.seed});

  factory DemoConfig.fromUri(Uri uri) {
    final q = uri.queryParameters;
    return DemoConfig(
      startRound: int.tryParse(q['from'] ?? '') ?? 0,
      autoplay: q.containsKey('demo'),
      failAt: int.tryParse(q['fail'] ?? ''),
      forceRetry: q.containsKey('retry'),
      seed: int.tryParse(q['seed'] ?? ''),
    );
  }

  final int startRound;
  final bool autoplay;
  final int? failAt;
  final bool forceRetry;
  final int? seed;

  bool get isActive => startRound > 0 || autoplay || forceRetry || seed != null;
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

  GamePhase _phase = GamePhase.menu;
  GamePhase get phase => _phase;
  set phase(GamePhase p) {
    _phase = p;
    revision.value++;
  }

  /// Bumps whenever the phase changes, so page widgets (scores, stage menu)
  /// can rebuild.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// True while the mouse is over a pressable button (for the cursor).
  final ValueNotifier<bool> overButton = ValueNotifier(false);

  /// Which layout the shell is showing: the wide web stage or the phone
  /// screen. A run keeps the platform it started with.
  bool wide = false;
  PlayPlatform get layoutPlatform => wide ? PlayPlatform.desktop : PlayPlatform.touch;

  /// False when the phone version is played with a mouse only (a narrow
  /// laptop window): rounds that need two fingers are left out.
  bool multiTouch = true;

  /// Mouse position over the game (null when it's elsewhere).
  Offset? hoverScreen;

  /// Fail shake: decays, and the offset grows with its square.
  double trauma = 0;

  String? _lastPressedId;
  double _tickTimer = 0;
  bool _tock = false;

  /// Seconds since the clock last beat (the arena pulses with it), and
  /// whether that beat was a tight one.
  double beatAge = 99;
  bool beatTight = false;

  /// Set from the platform's reduce-motion setting: no shake, no pulse.
  bool reduceMotion = false;
  RunEngine? engine;
  Round? round;
  ChaosState chaos = ChaosState.none;
  RunResult? lastResult;

  /// Announcement in the top strip ("NEW: Liars", "TRY AGAIN"). It is drawn
  /// only in its own strip, never over the instruction, timer or button.
  String banner = '';
  String bannerSub = '';
  double bannerTime = 0;
  double bannerDuration = 1;
  bool bannerIsAlarm = false;

  /// Chaos state the arena reads when drawing.
  double rotation = 0;
  Offset shakeOffset = Offset.zero;
  double flashInvert = 0; // brief full-screen invert flash on the reveal

  double _phaseTimer = 0;
  double _shakeTime = 0;

  // Mid-round swap.
  double? _swapAt;
  (int, int)? _swapPair;
  double _swapProgress = -1;
  (double, double, double, double)? _swapFrom;

  // Drift: buttons wander around their spot (home x, y, phase per button).
  List<(double, double, double)>? _driftHome;

  // Blackouts: moments (seconds into the round) when the lights cut out.
  List<double> _blackoutAt = const [];

  /// Seconds of blackout left (the arena draws a dead screen while > 0).
  double blackout = 0;

  /// Whether this round has already shouted HURRY.
  bool _hurried = false;

  final Map<int, String?> _pointerTargets = {};
  final Map<int, Offset> _pointerStart = {};

  late final ArenaComponent arena;

  @override
  Color backgroundColor() => BP.ink;

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
    _runStarted = now;
    _runVariant = dailyVariant;
    final platform = layoutPlatform;
    final e = mode == GameMode.daily
        ? RunEngine.daily(now, platform: platform, multiTouch: multiTouch)
        : RunEngine.endless(demo.seed ?? math.Random().nextInt(1 << 30), platform: platform, multiTouch: multiTouch);
    // Practice/demo links only apply to Endless, so Daily stays fair.
    if (mode == GameMode.endless && demo.isActive) {
      e.skipTo(demo.startRound);
      if (demo.forceRetry) e.retryChance = 1;
    }
    engine = e;
    _demoCooldown = 0;
    _demoHolding = null;
    trauma = 0;
    arena.fx.clear();
    store.countRun();
    overlays.removeAll(['menu', 'gameOver']);
    phase = GamePhase.playing;
    _clearBanner();
    _beginRound();
    // One soundtrack for the whole run: started here and nowhere else.
    audio.musicStart();
    _sendMix();
  }

  void backToMenu() {
    audio.musicStop();
    _clearBanner();
    phase = GamePhase.menu;
    round = null;
    overlays.removeAll(['gameOver']);
    overlays.add('menu');
  }

  void _beginRound() {
    final e = engine!;
    e.aspect = arena.aspect;
    final r = e.startRound();
    round = r;
    _lastPressedId = null;
    _clearBanner(); // an announcement never outlives its round
    // The clock and the soundtrack carry straight on into the new round:
    // nothing about the sound is reset here.
    _pointerStart.clear();
    for (final b in r.buttons) {
      b.pressed = false;
    }
    chaos = r.isCalm ? const ChaosState(calm: true, tempo: 0.8) : e.chaosFor(e.roundIndex);
    rotation = 0;
    _pointerTargets.clear();
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

    // Plan drift (never on the same round as a swap: one moves, the other
    // jumps) and blackouts. Both deterministic per round.
    _driftHome = null;
    if (chaos.drift > 0 && r.allowSwap && _swapAt == null && !reduceMotion) {
      final rng = SeededRng.derive(e.seed, [e.roundIndex, 'drift']);
      _driftHome = [for (final b in r.buttons) (b.x, b.y, rng.rangeDouble(0, math.pi * 2))];
    }
    blackout = 0;
    _hurried = false;
    _blackoutAt = const [];
    if (chaos.blackouts > 0 && r.showTimer && r.timeLimit > 0) {
      final rng = SeededRng.derive(e.seed, [e.roundIndex, 'blackout']);
      _blackoutAt = [
        r.timeLimit * rng.rangeDouble(0.22, 0.4),
        if (chaos.blackouts > 1) r.timeLimit * rng.rangeDouble(0.55, 0.7),
      ];
    }

    final unlocked = e.familiesUnlockingAt(e.roundIndex);
    if (unlocked.isNotEmpty && e.retries == 0) {
      _showBanner('NEW: ${unlocked.map((f) => f.title).join(' + ')}', 'New round types unlocked', 1.6);
    } else if (r.isCalm && e.retries == 0) {
      _showBanner('...', '', 1.0);
    }
  }

  /// The scene is upright, so the top strip is clear of everything the
  /// round draws. While a round rotates, its instruction and buttons can
  /// swing into the strip, so announcements wait.
  bool get _bannerClear => rotation.abs() < 1e-3;

  /// Whether the announcement is on screen now: only while a run is being
  /// played, and only when the strip is clear.
  bool get bannerShowing =>
      bannerTime > 0 &&
      banner.isNotEmpty &&
      _bannerClear &&
      (phase == GamePhase.playing || phase == GamePhase.roundWon);

  void _clearBanner() {
    banner = '';
    bannerTime = 0;
  }

  void _showBanner(String text, String sub, double seconds, {bool alarm = false}) {
    banner = text;
    bannerSub = sub;
    bannerTime = seconds;
    bannerDuration = seconds;
    bannerIsAlarm = alarm;
  }

  // ---------------------------------------------------------------------------
  // Loop
  // ---------------------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    // A held announcement keeps its time until it can be shown.
    if (bannerTime > 0 && _bannerClear) bannerTime -= dt;
    if (flashInvert > 0) flashInvert -= dt;
    trauma = math.max(0, trauma - dt * 1.6);
    _shakeTime += dt;
    _updateShake();
    _updateHover();

    if (phase == GamePhase.playing || phase == GamePhase.roundWon) _sendMix();

    switch (phase) {
      case GamePhase.playing:
        _updatePlaying(dt);
      case GamePhase.roundWon:
        _phaseTimer -= dt;
        if (_phaseTimer <= 0) {
          phase = GamePhase.playing;
          _beginRound();
        }
      case GamePhase.failing:
        // Let the failure land (shake, shatter, sound) before the screen.
        _phaseTimer -= dt;
        if (_phaseTimer <= 0) _finishLoss();
      case GamePhase.fakeGameOver:
        _phaseTimer -= dt;
        if (_phaseTimer <= 0) _revealTryAgain();
      case GamePhase.menu:
      case GamePhase.gameOver:
        break;
    }
  }

  /// Largest chaos sway while playing, and the extra tremor at the deadline,
  /// in pixels. Together they stay under [ArenaLayout.maxPlayShake], which
  /// keeps the announcement strip clear of the instruction.
  static const chaosShakePx = 7.0;
  static const deadlineTremorPx = 2.2;

  /// Smooth, deliberate shake: chaos sway (only while playing) plus fail trauma.
  void _updateShake() {
    final t = _shakeTime;
    if (reduceMotion) {
      shakeOffset = Offset.zero;
      return;
    }
    var amp = trauma * trauma * 16;
    if (phase == GamePhase.playing && chaos.shake > 0) amp += chaos.shake * chaosShakePx;
    // A small tremor in the last moments of a timed round.
    final r = round;
    if (phase == GamePhase.playing && r != null && r.showTimer && !r.isCalm && r.timeLimit > 0 && r.verdict == Verdict.pending) {
      final f = r.timeLeft / r.timeLimit;
      if (f < 0.2) amp += (0.2 - f) / 0.2 * deadlineTremorPx;
    }
    if (amp < 0.05) {
      shakeOffset = Offset.zero;
      return;
    }
    shakeOffset = Offset(
      amp * (math.sin(t * 37) * 0.6 + math.sin(t * 23.3 + 1) * 0.4),
      amp * (math.sin(t * 31.7 + 2) * 0.6 + math.sin(t * 19.1) * 0.4),
    );
  }

  void _updateHover() {
    final r = round;
    final h = hoverScreen;
    var over = false;
    if (r != null && phase == GamePhase.playing) {
      if (h != null) {
        final q = arena.toPlay(h);
        r.onHover(q.dx, q.dy);
        over = arena.hitTest(h, r) != null;
      } else {
        r.onHover(null, null);
      }
    }
    if (overButton.value != over) overButton.value = over;
  }

  /// Tells the soundtrack where the run is: the round sets its tempo, layers
  /// and key; the time left sets how much it panics. Between rounds the
  /// panic eases off, but the music itself never stops or restarts.
  void _sendMix() {
    final r = round;
    final e = engine;
    if (r == null || e == null) return;
    final timed = r.showTimer && r.timeLimit > 0;
    final pending = phase == GamePhase.playing && r.verdict == Verdict.pending;
    final f = timed ? (r.timeLeft / r.timeLimit).clamp(0.0, 1.0) : 1.0;
    audio.musicSet(SoundtrackMix.at(
      roundIndex: r.ctx.roundIndex,
      timeFraction: pending ? f : 1.0,
      timed: timed,
      calm: r.isCalm,
    ));
  }

  /// The beat. On the web the soundtrack is the beat and the arena pulses
  /// with it. Elsewhere it's the clock: tick, tock, tick, tock, closing up
  /// as the time drains and as the run goes on, never restarted by a round.
  void _updateTicks(Round r, double dt) {
    beatAge += dt;
    if (audio.hasMusic) {
      final age = audio.musicBeatAge();
      if (age >= 0) {
        beatAge = age;
        beatTight = Soundtrack.tightBeat(audio.lastMix?.urgency ?? 0);
      }
      return;
    }
    if (r.verdict != Verdict.pending) return;
    final timed = r.showTimer && r.timeLimit > 0;
    final f = timed ? (r.timeLeft / r.timeLimit).clamp(0.0, 1.0) : 1.0;
    if (timed && r.timeLeft <= 0) return;
    _tickTimer -= dt;
    if (_tickTimer > 0) return;
    final tight = ClockBeat.tight(timeFraction: f, timed: timed, calm: r.isCalm);
    audio.playClock(tock: _tock, tight: tight);
    if (tight) haptics.tick();
    _tock = !_tock;
    beatAge = 0;
    beatTight = tight;
    _tickTimer += ClockBeat.interval(timeFraction: f, roundIndex: r.ctx.roundIndex, timed: timed, calm: r.isCalm);
    if (_tickTimer < 0) _tickTimer = 0;
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
      final ids = move.substring(5).split(',');
      _demoHolding = move.substring(5);
      for (final id in ids) {
        _setPressed(r, id, true);
        r.onPressDown(id);
      }
    } else if (move.startsWith('key:')) {
      keyDown(move.substring(4));
    } else if (move.startsWith('hover:')) {
      final b = r.buttons.firstWhere((b) => b.id == move.substring(6));
      final p = arena.playRect;
      hoverScreen = Offset(p.left + b.x * p.width, p.top + b.y * p.height);
    } else if (move.startsWith('swipe:')) {
      final parts = move.split(':');
      final id = parts[1];
      r.onPressDown(id);
      r.onDrag(id, double.parse(parts[2]), double.parse(parts[3]));
      r.onPressUp(id);
      _lastPressedId = id;
    } else if (move.startsWith('rub:')) {
      final sr = r as dynamic;
      sr.demoRub(dt * 4);
      _demoCooldown = 0;
      return;
    } else {
      _demoTap(r, move);
    }
    _demoCooldown = 0.2;
  }

  void _demoTap(Round r, String id) {
    if (id.isEmpty) return;
    _lastPressedId = id;
    _setPressed(r, id, true);
    audio.playPress();
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
      for (final id in _demoHolding!.split(',')) {
        _setPressed(r, id, false);
      }
      _demoHolding = null;
    }
    _updateSwap(r, dt);
    _updateDrift(r);
    _updateBlackout(r, dt);
    _updateHurry(r);
    _updateTicks(r, dt);

    // Chaos layers.
    rotation += chaos.rotationSpeed * dt;

    if (r.verdict == Verdict.success) {
      blackout = 0;
      engine!.completeRound(r);
      audio.playClear();
      haptics.success();
      arena.onSuccess(r, _lastPressedId);
      phase = GamePhase.roundWon;
      _phaseTimer = 0.46;
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
      audio.playGlitch();
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

  /// Buttons wander on two slow, out-of-step waves, so you have to chase
  /// them. They stop the moment the round is decided.
  void _updateDrift(Round r) {
    final home = _driftHome;
    if (home == null || r.verdict != Verdict.pending || home.length != r.buttons.length) return;
    final t = r.elapsed;
    final amp = 0.07 * chaos.drift;
    final ramp = (t / 0.4).clamp(0.0, 1.0); // ease in, no jump on appear
    for (var i = 0; i < r.buttons.length; i++) {
      final b = r.buttons[i];
      final (hx, hy, ph) = home[i];
      final ry = b.radius;
      final rx = b.radius / math.max(0.2, r.ctx.aspect);
      b
        ..x = (hx + math.sin(t * 2.1 + ph) * amp * ramp).clamp(rx, 1 - rx)
        ..y = (hy + math.sin(t * 1.7 + ph * 1.3) * amp * ramp).clamp(ry, 1 - ry);
    }
  }

  /// The lights cut out for a fraction of a second. Presses still count.
  void _updateBlackout(Round r, double dt) {
    if (blackout > 0) blackout = math.max(0, blackout - dt);
    if (_blackoutAt.isEmpty || r.verdict != Verdict.pending) return;
    if (r.elapsed >= _blackoutAt.first) {
      _blackoutAt = _blackoutAt.sublist(1);
      blackout = 0.22;
      audio.playGlitch();
      haptics.chaos();
    }
  }

  /// Once per round, from round 4, the strip shouts when time is nearly up.
  void _updateHurry(Round r) {
    if (_hurried || r.isCalm || !r.showTimer || r.timeLimit <= 0 || r.verdict != Verdict.pending) return;
    if (r.ctx.roundIndex < 3 || banner.isNotEmpty && bannerTime > 0) return;
    if (r.timeLeft / r.timeLimit < 0.3) {
      _hurried = true;
      const words = ['HURRY', 'NOW', 'PRESS IT', 'TOO SLOW', 'GO GO GO'];
      _showBanner(words[(r.ctx.roundIndex * 7 + engine!.seed) % words.length], '', 0.7, alarm: true);
      audio.playBuzz();
    }
  }

  void _handleLoss(Round r) {
    blackout = 0;
    audio.musicDuck(true); // the music drops out under the fail
    audio.playFail();
    haptics.fail();
    trauma = 1;
    arena.onFail(r, _lastPressedId);
    for (final b in r.buttons) {
      b.pressed = false;
    }
    _clearBanner();
    phase = GamePhase.failing;
    _phaseTimer = 0.62;
  }

  void _finishLoss() {
    final r = round!;
    final e = engine!;
    final outcome = e.registerLoss();
    if (demo.forceRetry) e.retryChance = Difficulty.retryChance; // only once
    if (outcome == LossOutcome.tryAgain) {
      // Show a game-over screen identical to the real one...
      lastResult = _buildResult(r, save: false);
      phase = GamePhase.fakeGameOver;
      _phaseTimer = Difficulty.fakeGameOverSeconds;
      overlays.add('gameOver');
    } else {
      audio.musicStop();
      phase = GamePhase.gameOver;
      lastResult = _buildResult(r, save: true);
      overlays.add('gameOver');
    }
  }

  /// ...then reveal you're still alive, and the clock is already running.
  void _revealTryAgain() {
    overlays.remove('gameOver');
    audio.musicDuck(false); // same soundtrack, straight back in where it was
    audio.playReveal();
    haptics.chaos();
    flashInvert = 0.12;
    phase = GamePhase.playing;
    _beginRound();
    _showBanner('TRY AGAIN  ·  LESS TIME', '', 1.4, alarm: true);
  }

  /// When the current run started. A Daily is scored against the day it was
  /// started on, even if it ends after midnight.
  DateTime? _runStarted;
  String _runVariant = '';

  /// Which Daily this device plays right now: the desktop one, the phone one,
  /// or the phone one without the two-thumb round. Each has its own rounds,
  /// so each keeps its own score.
  String get dailyVariant => layoutPlatform == PlayPlatform.desktop ? 'desktop' : (multiTouch ? '' : 'mouse');

  RunResult _buildResult(Round r, {required bool save}) {
    final e = engine!;
    final now = e.mode == GameMode.daily ? (_runStarted ?? clock()) : clock();
    final score = e.score;
    if (isPractice) save = false; // practice and demo runs never count
    if (e.mode == GameMode.daily) {
      final existing = store.dailyFor(now, variant: _runVariant);
      final best = math.max(existing?.bestScore ?? 0, score);
      final isNewBest = existing != null && score > existing.bestScore;
      if (save) store.recordDaily(now, score, variant: _runVariant);
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
    _pointerStart[pointer] = position;
    if (target != null) _lastPressedId = target;
    if (target != null) {
      for (final b in r.buttons) {
        if (b.id == target) {
          b.pressed = true;
          audio.playPress();
          haptics.tap();
        }
      }
    }
    r.onPressDown(target);
  }

  void pointerMove(int pointer, Offset position) {
    final start = _pointerStart[pointer];
    final r = round;
    if (start == null || r == null || phase != GamePhase.playing || r.verdict != Verdict.pending) return;
    final h = math.max(1.0, arena.playRect.height);
    final d = position - start;
    r.onDrag(_pointerTargets[pointer], d.dx / h, d.dy / h);
  }

  /// Mouse moved over the game (null: it left).
  void hover(Offset? position) => hoverScreen = position;

  /// A key press while playing. Returns true if the game used it.
  bool keyDown(String key) {
    final r = round;
    if (phase != GamePhase.playing || r == null || r.verdict != Verdict.pending) return false;
    audio.playPress();
    r.onKey(key);
    return true;
  }

  void pointerUp(int pointer) {
    if (!_pointerTargets.containsKey(pointer)) return;
    _pointerStart.remove(pointer);
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

  /// Bumps when sound or vibration is switched, so every switch on screen
  /// (menu chips, the phone's corner switch) shows the same state, including
  /// after M is pressed on the keyboard.
  final ValueNotifier<int> settingsRevision = ValueNotifier(0);

  void setSound(bool on) {
    audio.enabled = on;
    store.setSoundOn(on);
    settingsRevision.value++;
  }

  void setHaptics(bool on) {
    haptics.enabled = on;
    store.setHapticsOn(on);
    settingsRevision.value++;
  }

  @visibleForTesting
  void debugSetRound(Round r) => round = r;
}
