import '../logic/rng.dart';
import 'round.dart';

/// Spots in the play area for [count] buttons (normalised 0..1).
List<(double, double)> slotsFor(int count) {
  switch (count) {
    case 1:
      return const [(0.5, 0.5)];
    case 2:
      return const [(0.28, 0.5), (0.72, 0.5)];
    case 3:
      return const [(0.5, 0.25), (0.25, 0.72), (0.75, 0.72)];
    case 4:
      return const [(0.27, 0.28), (0.73, 0.28), (0.27, 0.74), (0.73, 0.74)];
    default:
      // 5 or 6: two rows of three.
      return const [(0.2, 0.3), (0.5, 0.3), (0.8, 0.3), (0.2, 0.72), (0.5, 0.72), (0.8, 0.72)].take(count).toList();
  }
}

double radiusFor(int count) => switch (count) {
  1 => 0.24,
  2 => 0.2,
  3 || 4 => 0.17,
  _ => 0.13,
};

/// Places [buttons] in shuffled slots.
void placeInSlots(List<GameButton> buttons, SeededRng rng) {
  final slots = rng.shuffled(slotsFor(buttons.length));
  final r = radiusFor(buttons.length);
  for (var i = 0; i < buttons.length; i++) {
    buttons[i]
      ..x = slots[i].$1
      ..y = slots[i].$2
      ..radius = r;
  }
}

/// A random spot for a single button, kept away from the edges.
(double, double) randomSpot(SeededRng rng) => (rng.rangeDouble(0.25, 0.75), rng.rangeDouble(0.28, 0.72));

/// [count] distinct random colours.
List<GameColour> distinctColours(SeededRng rng, int count) => rng.shuffled(GameColour.all).take(count).toList();
