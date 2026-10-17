import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The one visual identity: a control room at 3am, and something is wrong.
///
/// Near-black panels, bone-white type, one alarm red and one sodium amber.
/// Flat, square-edged slabs with hairline rules instead of cartoon outlines
/// and offset shadows. A dark red flood rises as the clock runs out and the
/// edges of the screen pulse red like a pulse in your ears. Display type is
/// Anton (tall, condensed, shouting); small text is Manrope.
///
/// Naming note: [ink] is the BACKGROUND colour and [paper] is the FOREGROUND
/// colour. The names go back to an earlier theme; every screen reads them.
class BP {
  // Background.
  static const ink = Color(0xFF0B0C0E);
  static const line = Color(0xFF2B2E33); // hairline rules on the background

  // Foreground.
  static const paper = Color(0xFFECE8E1);
  static const muted = Color(0xFFA7A197);
  static const faint = Color(0xFF6F6B64);

  // Signals.
  static const signal = Color(0xFFFF2B39); // the button, the deadline, failure
  static const hazard = Color(0xFFF0A81C); // sodium amber: warnings, the round tag
  static const flood = Color(0xFF3A0A0F); // the rising panic: dark arterial red
  static const calm = Color(0xFFA9C4E0); // calm rounds: cold, not cheerful
  static const calmBg = Color(0xFF0C1520);

  // Supporting tones.
  static const cream = Color(0xFFF6F3EE); // brightest type: big numbers, labels on red
  static const blood = Color(0xFF8C1018); // the deep red under red: report bars, shadows
  static const inkSoft = Color(0xFF1C1F23); // raised panels on the background
  static const panel = Color(0xFF131518); // bars and cards
  static const onInk = Color(0xFF8E8981); // quiet labels on dark panels
  static const rim = Color(0xFF020203); // button rims: near black

  static const display = 'Anton';
  static const text = 'Manrope';

  static const tabular = [FontFeature.tabularFigures()];

  static TextStyle d(double size, {Color color = paper, FontWeight weight = FontWeight.w400, double height = 1.0, double spacing = 0}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        color: color,
        fontWeight: FontWeight.w400,
        height: height,
        letterSpacing: spacing,
        fontFeatures: tabular,
      );

  static TextStyle t(double size, {Color color = paper, FontWeight weight = FontWeight.w700, double height = 1.4, double spacing = 0}) =>
      TextStyle(fontFamily: text, fontSize: size, color: color, fontWeight: weight, height: height, letterSpacing: spacing);

  /// Labels: chunky capitals, lightly spaced.
  static TextStyle label(double size, {Color color = muted}) => TextStyle(
    fontFamily: text,
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w800,
    letterSpacing: size * 0.08,
    height: 1.2,
    fontFeatures: tabular,
  );

  /// Spacing scale.
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0, s7 = 48.0, s8 = 64.0;

  /// Outline width for buttons and cards, scaled to their size.
  static double outline(double r) => (r * 0.07).clamp(2.5, 6.0);

  static Color shade(Color c, double amount) => Color.lerp(c, const Color(0xFF000000), amount)!;
  static Color tint(Color c, double amount) => Color.lerp(c, const Color(0xFFFFFFFF), amount)!;

  /// Card corners and slab corners: barely rounded, machined.
  static const radius = 3.0;

  /// Faint horizontal scanlines: one tiny tile repeated by a shader, so the
  /// whole screen costs a single rectangle fill. Built once per colour.
  static final Map<Color, Paint> _linePaints = {};
  static final _identity = Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  /// Paint that fills an area with 1px lines of [line] every 3px.
  static Paint scanlines(Color line) => _linePaints.putIfAbsent(line, () {
    const w = 4, h = 3;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 4, 1), Paint()..color = line);
    final tile = rec.endRecording().toImageSync(w, h);
    return Paint()..shader = ImageShader(tile, TileMode.repeated, TileMode.repeated, _identity);
  });
}
