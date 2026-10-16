import 'dart:math' as math;
import 'dart:ui';

/// Where everything sits on the play screen, for one screen size. Pure
/// geometry, so it is tested on its own (see test/announcement_test.dart).
///
/// From the top: a thin strip (the round number on the left, announcements
/// in the middle, the sound word on the phone's right), then the
/// instruction, then the play area where the buttons and their timers live.
class ArenaLayout {
  const ArenaLayout(this.screen, {required this.wide});

  final Size screen;
  final bool wide;

  double get pad => wide ? 28 : 16;
  double get hudHeight => wide ? 64 : 56;

  /// Room kept clear at the top right of the phone for the SOUND word.
  static const phoneSoundRoom = 84.0;

  /// The most the scene can shake while a round is being played (chaos sway
  /// plus the deadline tremor), in pixels.
  static const maxPlayShake = 9.5;

  Rect get columnRect {
    final w = wide ? screen.width : math.min(screen.width, 560.0);
    return Rect.fromLTWH((screen.width - w) / 2, 0, w, screen.height);
  }

  double get instructionHeight => wide ? 104 : math.max(128, screen.height * 0.2);

  Rect get instructionRect {
    final c = columnRect;
    return Rect.fromLTWH(c.left + pad, hudHeight, c.width - 2 * pad, instructionHeight);
  }

  /// Where buttons live. Positions in rounds are 0..1 inside this rect.
  Rect get playRect {
    final c = columnRect;
    final top = instructionRect.bottom + (wide ? 8 : 12);
    final bottom = screen.height - 28;
    return Rect.fromLTRB(c.left + pad, top, c.right - pad, math.max(top + 120, bottom));
  }

  /// Where announcements ("NEW: LIARS", "TRY AGAIN") are drawn, clipped to
  /// it: the top strip between the round number ([hudTextWidth] wide) and the
  /// sound word, ending well above the instruction even with the scene
  /// shaking. Empty when the screen is too narrow to fit one.
  Rect bannerRect(double hudTextWidth) {
    final c = columnRect;
    var inset = pad + hudTextWidth + 16;
    if (!wide) inset = math.max(inset, phoneSoundRoom);
    final left = c.left + inset;
    final right = math.max(left, c.right - inset);
    return Rect.fromLTRB(left, 0, right, hudHeight - 12 - maxPlayShake);
  }
}
