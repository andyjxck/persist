import 'calm_round.dart';
import 'fake_rounds.dart';
import 'liar_rounds.dart';
import 'memory_rounds.dart';
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
];

/// Used by the engine for suspiciously calm rounds.
const RoundType calmRoundType = CalmType();
