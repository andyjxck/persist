import 'calm_round.dart';
import 'desktop_rounds.dart';
import 'touch_rounds.dart';
import 'fake_rounds.dart';
import 'liar_rounds.dart';
import 'memory_rounds.dart';
import 'remember_rounds.dart';
import 'round.dart';
import 'runner_rounds.dart';
import 'simple_rounds.dart';

/// Every round type in the game. To add new chaos: write a [RoundType] and a
/// [Round] subclass, then add the type here. Append new types to the END of
/// the list so existing Daily sequences don't shift.
const List<RoundType> allRoundTypes = [
  PressItType(),
  DontPressType(),
  PressNTimesType(),
  HoldItType(),
  ShrinkerType(),
  DodgerType(),
  ColourLiarType(),
  RoundsAgoType(),
  RewriteType(),
  FakeNotificationType(),
  DecoyType(),
  FlashSequenceType(),
  FakeLoadingType(),
  FakeWinType(),
  RememberType(),
  RecallType(),
];

/// Rounds only the web/desktop version draws (cursor, keyboard, wide stage).
const List<RoundType> desktopRoundTypes = [ChaseType(), KeyTrapType(), HoverHoldType(), MagnetType(), GridType()];

/// Rounds only the mobile version draws (flicks, two thumbs, rubbing).
const List<RoundType> touchRoundTypes = [FlickType(), BothThumbsType(), ScratchType()];

/// Touch rounds that need two fingers down at once. Left out when the phone
/// version is played with only a mouse (a narrow laptop window).
const Set<String> multiTouchRoundIds = {'both_thumbs'};

/// The full pool for one version of the game. Shared rounds come first, in
/// their original order, so each version's Daily stays stable.
/// [multiTouch] false drops rounds a single mouse pointer can't win.
List<RoundType> roundTypesFor(PlayPlatform platform, {bool multiTouch = true}) => [
  ...allRoundTypes,
  ...(platform == PlayPlatform.desktop
      ? desktopRoundTypes
      : touchRoundTypes.where((t) => multiTouch || !multiTouchRoundIds.contains(t.id))),
];

/// Used by the engine for suspiciously calm rounds.
const RoundType calmRoundType = CalmType();
