import 'package:flutter/painting.dart';

/// The one visual identity, used by the game canvas and every screen.
///
/// Near-black void, one cold off-white for words, greys for everything
/// quieter, and the button's own colours as the only colour on screen.
/// Type: Manrope (bundled, SIL OFL), set small, spaced and sparse.
class BP {
  // The void.
  static const ink = Color(0xFF050505);
  static const line = Color(0xFF1E1E1E);

  // Words.
  static const paper = Color(0xFFE4E4E2);
  static const muted = Color(0xFF8C8C8A);
  static const faint = Color(0xFF4E4E4C);

  // Signals.
  static const signal = Color(0xFFFF3B4E); // the button, the deadline, failure
  static const calm = Color(0xFF8193A8); // calm rounds: cold, not cheerful
  static const calmBg = Color(0xFF05070A);

  static const display = 'Manrope';
  static const text = 'Manrope';

  static const tabular = [FontFeature.tabularFigures()];

  static TextStyle d(double size, {Color color = paper, FontWeight weight = FontWeight.w700, double height = 1.05, double spacing = 0}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        fontFeatures: tabular,
      );

  static TextStyle t(double size, {Color color = paper, FontWeight weight = FontWeight.w500, double height = 1.45, double spacing = 0}) =>
      TextStyle(fontFamily: text, fontSize: size, color: color, fontWeight: weight, height: height, letterSpacing: spacing);

  /// Small, widely spaced capitals: the only kind of label there is.
  static TextStyle label(double size, {Color color = muted}) => TextStyle(
    fontFamily: text,
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    letterSpacing: size * 0.32,
    height: 1.2,
    fontFeatures: tabular,
  );

  /// Spacing scale.
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0, s7 = 48.0, s8 = 64.0;

  static Color shade(Color c, double amount) => Color.lerp(c, const Color(0xFF000000), amount)!;
  static Color tint(Color c, double amount) => Color.lerp(c, const Color(0xFFFFFFFF), amount)!;
}
