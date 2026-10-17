import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The one visual identity: a warning label that is losing its temper.
///
/// Cream paper, heavy black ink, thick outlines and hard offset shadows,
/// hazard tape at the edges, and a red flood that rises up the screen as the
/// clock runs out. Display type is Anton (tall, condensed, shouting); small
/// text is Manrope ExtraBold.
///
/// Naming note: [ink] is the BACKGROUND (paper) colour and [paper] is the
/// FOREGROUND (ink) colour. The names are kept from the old dark theme so
/// every screen flipped over in one place.
class BP {
  // Background.
  static const ink = Color(0xFFF4EEE2);
  static const line = Color(0xFFD9D0BF);

  // Foreground.
  static const paper = Color(0xFF111111);
  static const muted = Color(0xFF4B463E);
  static const faint = Color(0xFF8C8578);

  // Signals.
  static const signal = Color(0xFFFF2E3F); // the button, the deadline, failure
  static const hazard = Color(0xFFFFD000); // tape, the HUD, highlights
  static const flood = Color(0xFFFFB3BA); // the rising panic
  static const calm = Color(0xFF2F4D6E); // calm rounds: cold, not cheerful
  static const calmBg = Color(0xFFDDE6EE);

  // Supporting tones for the overhauled screens.
  static const cream = Color(0xFFFFF8EA); // card faces and light type on ink
  static const blood = Color(0xFFC81E2E); // the deep red under red: shadows, stripes
  static const inkSoft = Color(0xFF2A2621); // panels inside black bars
  static const onInk = Color(0xFFB9B0A0); // quiet labels on black

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

  /// Card corners and slab corners.
  static const radius = 10.0;

  /// A printed-paper halftone: one tiny tile of dots, repeated by a shader
  /// so the whole screen costs a single rectangle fill. Built once.
  static final Map<Color, Paint> _dotPaints = {};
  static final _identity = Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  /// Paint that fills an area with halftone dots of [dot] (alpha included).
  static Paint dots(Color dot) => _dotPaints.putIfAbsent(dot, () {
    const s = 22.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..color = dot;
    c.drawCircle(const Offset(s * 0.25, s * 0.25), 1.2, p);
    c.drawCircle(const Offset(s * 0.75, s * 0.75), 1.2, p);
    final tile = rec.endRecording().toImageSync(s.toInt(), s.toInt());
    return Paint()..shader = ImageShader(tile, TileMode.repeated, TileMode.repeated, _identity);
  });
}
