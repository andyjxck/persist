import 'dart:math' as math;
import 'dart:ui';

import 'layout.dart';
import 'round.dart';

// Overlay rects are normalised to the play area, like button positions.

// ---------------------------------------------------------------------------
// A fake loading screen. The clock keeps running underneath it.
// ---------------------------------------------------------------------------

class FakeLoadingType extends RoundType {
  const FakeLoadingType();
  @override
  String get id => 'fake_loading';
  @override
  RoundFamily get family => RoundFamily.fake;
  @override
  int get unlockRound => 15;
  @override
  double weight(int roundIndex) => 0.8;
  @override
  Round create(RoundContext ctx) => FakeLoadingRound(ctx);
}

class FakeLoadingRound extends Round {
  @override
  String? demoMove() => elapsed < 0.8 ? null : 'main';

  FakeLoadingRound(super.ctx) {
    final rng = ctx.rng;
    final spot = randomSpot(rng);
    button = GameButton(id: 'main', colour: rng.pick(GameColour.all), x: spot.$1, y: spot.$2);
    _overlay = FakeOverlay(
      id: 'loading',
      kind: FakeKind.loading,
      rect: const Rect.fromLTWH(0, 0, 1, 1),
      title: rng.pick(const ['Loading next round...', 'Saving your score...', 'Connecting...']),
      body: 'Please wait',
      // Taps go straight through to the button you can barely see.
      blocksInput: false,
    );
    appearAt = 0.25;
  }

  late final GameButton button;
  late final FakeOverlay _overlay;
  late final double appearAt;

  @override
  String get instruction => 'Press it';
  @override
  String get hint => elapsed > appearAt ? 'The clock is still running' : '';
  @override
  List<GameButton> get buttons => [button];
  @override
  List<FakeOverlay> get overlays => elapsed > appearAt ? [_overlay] : const [];
  @override
  double get baseTime => 3.0;

  @override
  void tick(double dt) {
    // A progress bar that crawls, stalls, then jumps. Classic.
    final f = (elapsed - appearAt) / timeLimit;
    _overlay.progress = (f < 0.5 ? f * 1.6 : 0.8 + (f - 0.5) * 0.05).clamp(0, 0.99);
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'main') succeed();
  }

  @override
  void onTimeout() => fail('It was never loading. The clock was running.');
}

// ---------------------------------------------------------------------------
// A fake "YOU WIN!" with a tempting prize button.
// ---------------------------------------------------------------------------

class FakeWinType extends RoundType {
  const FakeWinType();
  @override
  String get id => 'fake_win';
  @override
  RoundFamily get family => RoundFamily.fake;
  @override
  int get unlockRound => 18;
  @override
  double weight(int roundIndex) => 0.8;
  @override
  Round create(RoundContext ctx) => FakeWinRound(ctx);
}

class FakeWinRound extends Round {
  @override
  String? demoMove() => elapsed < 0.7 ? null : 'main';

  FakeWinRound(super.ctx) {
    final rng = ctx.rng;
    target = rng.range(2, 3);
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      label: '$target',
      x: rng.rangeDouble(0.3, 0.7),
      y: 0.8,
      radius: 0.15,
    );
    _overlay = FakeOverlay(
      id: 'prize',
      kind: FakeKind.win,
      rect: const Rect.fromLTRB(0.06, 0.02, 0.94, 0.58),
      title: rng.pick(const ['YOU WIN!', 'NEW HIGH SCORE!', 'CONGRATULATIONS!']),
      body: rng.pick(const ['You beat the button.', 'Top 1% of all players!', 'Nothing more to do here.']),
      buttonLabel: rng.pick(const ['COLLECT PRIZE', 'CLAIM REWARD', 'CONTINUE']),
    );
  }

  late final int target;
  late final GameButton button;
  late final FakeOverlay _overlay;
  int count = 0;
  static const appearAt = 0.35;

  @override
  String get instruction => 'Press it $target times';
  @override
  List<GameButton> get buttons => [button];
  @override
  List<FakeOverlay> get overlays => elapsed > appearAt ? [_overlay] : const [];
  @override
  double get baseTime => 1.8 + 0.5 * target;
  @override
  bool get allowSwap => false;

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'prize') {
      fail('There is no prize. There is only the button.');
    } else if (targetId == 'main') {
      count++;
      button.label = '${target - count}';
      if (count >= target) succeed();
    }
  }

  @override
  void onTimeout() =>
      fail(count == 0 ? "You didn't win. You didn't press it either." : 'Only $count of $target presses.');
}

// ---------------------------------------------------------------------------
// A fake notification slides over the button.
// ---------------------------------------------------------------------------

class FakeNotificationType extends RoundType {
  const FakeNotificationType();
  @override
  String get id => 'fake_notification';
  @override
  RoundFamily get family => RoundFamily.fake;
  @override
  int get unlockRound => 9;
  @override
  Round create(RoundContext ctx) => FakeNotificationRound(ctx);
}

class FakeNotificationRound extends Round {
  @override
  String? demoMove() => overlays.isNotEmpty || elapsed < appearAt + 0.1 ? null : 'main';

  FakeNotificationRound(super.ctx) {
    final rng = ctx.rng;
    button = GameButton(
      id: 'main',
      colour: rng.pick(GameColour.all),
      x: rng.rangeDouble(0.3, 0.7),
      y: rng.rangeDouble(0.35, 0.65),
    );
    final message = rng.pick(const [
      ('Battery 1%', 'Tap to dismiss'),
      ('New message from Mum', 'Call me when you can'),
      ('Score saved', 'Tap to see your stats'),
      ('Update available', 'Tap to install now'),
      ('Low storage', 'Tap to free up space'),
    ]);
    _overlay = FakeOverlay(
      id: 'notification',
      kind: FakeKind.notification,
      rect: Rect.zero,
      title: message.$1,
      body: message.$2,
    );
    stayFor = timeLimit * 0.4;
  }

  late final GameButton button;
  late final FakeOverlay _overlay;
  late final double stayFor;
  static const appearAt = 0.2;
  static const slideTime = 0.18;

  @override
  String get instruction => 'Press it';
  @override
  List<GameButton> get buttons => [button];
  @override
  List<FakeOverlay> get overlays {
    final t = elapsed - appearAt;
    if (t < 0 || t > stayFor + 2 * slideTime) return const [];
    return [_overlay];
  }

  @override
  double get baseTime => 3.2;

  @override
  void tick(double dt) {
    // Slides in from the left, sits right on top of the button, slides out right.
    final t = elapsed - appearAt;
    double offset;
    if (t < slideTime) {
      offset = -1 + t / slideTime;
    } else if (t < slideTime + stayFor) {
      offset = 0;
    } else {
      offset = (t - slideTime - stayFor) / slideTime;
    }
    final eased = offset.sign * math.pow(offset.abs(), 2).toDouble();
    const h = 0.2;
    _overlay.rect = Rect.fromLTWH(0.04 + eased * 1.1, button.y - h / 2, 0.92, h);
  }

  @override
  void onPressDown(String? targetId) {
    if (targetId == 'notification') {
      fail('That was a fake notification.');
    } else if (targetId == 'main') {
      succeed();
    }
  }
}
