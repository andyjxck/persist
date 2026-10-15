import 'package:flutter/painting.dart';

/// The one visual identity, used by the game canvas and every screen.
///
/// Type: Unbounded (display: titles, instructions, numbers) paired with
/// Manrope (text: hints, body, labels). Both bundled under the SIL OFL.
/// Palette: warm ink background, one signal red, warm off-white text.
class BP {
  // Surfaces.
  static const ink = Color(0xFF0D0C12);
  static const ink2 = Color(0xFF14121B);
  static const surface = Color(0xFF1A1823);
  static const surfaceHi = Color(0xFF221F2D);
  static const line = Color(0xFF2C2938);
  static const lineSoft = Color(0x1FFFFFFF);

  // Text.
  static const paper = Color(0xFFF5F1E8);
  static const muted = Color(0xFFA29DAE);
  static const faint = Color(0xFF6D687A);

  // Signals.
  static const signal = Color(0xFFFF3B4E); // the button, primary actions
  static const amber = Color(0xFFFFB020); // warning
  static const mint = Color(0xFF2BD98A); // success
  static const calm = Color(0xFF8EC5FF); // calm rounds
  static const calmBg = Color(0xFF101B2B);

  static const display = 'Unbounded';
  static const text = 'Manrope';

  static const tabular = [FontFeature.tabularFigures()];

  static TextStyle d(double size, {Color color = paper, FontWeight weight = FontWeight.w800, double height = 1.05, double spacing = 0}) =>
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

  /// Small all-caps label (eyebrows, chips, HUD).
  static TextStyle label(double size, {Color color = muted}) =>
      TextStyle(fontFamily: text, fontSize: size, color: color, fontWeight: FontWeight.w800, letterSpacing: size * 0.14, height: 1.2);

  /// Spacing scale.
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0, s7 = 48.0, s8 = 64.0;

  static Color shade(Color c, double amount) => Color.lerp(c, const Color(0xFF000000), amount)!;
  static Color tint(Color c, double amount) => Color.lerp(c, const Color(0xFFFFFFFF), amount)!;
}
