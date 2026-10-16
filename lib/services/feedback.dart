import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound effects. Every file in assets/audio is synthesised by
/// tool/make_sounds.py for this game (no samples, no licences): a dry clock
/// escapement, a press click, a latch and a thud. There is no music: the
/// clock is the soundtrack. Every sound is preloaded into a small pool of
/// ready players, so nothing is created or decoded while you play. Every
/// call fails quietly, so a browser that blocks audio never breaks the game.
class GameAudio {
  bool enabled = true;
  bool _loaded = false;
  final Map<String, AudioPool> _pools = {};

  static const tick = 'tick.wav';
  static const tock = 'tock.wav';
  static const tickTight = 'tick_tight.wav';
  static const tockTight = 'tock_tight.wav';
  static const press = 'press.wav';
  static const clear = 'clear.wav';
  static const fail = 'fail.wav';
  static const reveal = 'reveal.wav';

  static const files = [tick, tock, tickTight, tockTight, press, clear, fail, reveal];

  /// Players kept ready per sound: enough for the fastest overlap.
  static int poolSize(String file) => switch (file) {
    press => 4,
    tick || tock || tickTight || tockTight => 3,
    _ => 1,
  };

  Future<void> preload() async {
    if (_loaded) return;
    try {
      await FlameAudio.audioCache.loadAll(files);
      for (final f in files) {
        _pools[f] = await FlameAudio.createPool(f, minPlayers: 1, maxPlayers: poolSize(f));
      }
      _loaded = true;
    } catch (e) {
      debugPrint('Audio preload failed: $e');
    }
  }

  Future<void> _play(String file, double volume) async {
    if (!enabled) return;
    final pool = _pools[file];
    if (pool == null) return; // not loaded (yet): stay silent rather than stall
    try {
      await pool.start(volume: volume);
    } catch (e) {
      debugPrint('Audio play failed: $e');
    }
  }

  void playPress() => _play(press, 0.75);
  void playClear() => _play(clear, 0.6);
  void playFail() => _play(fail, 1.0);
  void playReveal() => _play(reveal, 0.9);

  /// One beat of the clock. [tock] alternates the two halves of the
  /// escapement; [tight] switches to the shorter, harder pair near the end.
  void playClock({required bool tock, bool tight = false}) {
    final file = tight ? (tock ? tockTight : tickTight) : (tock ? GameAudio.tock : tick);
    _play(file, tight ? 0.8 : 0.62);
  }
}

/// Phone vibrations. Off on the web (browsers block or ignore them) and when
/// switched off in settings.
class GameHaptics {
  bool enabled = true;
  bool get _on => enabled && !kIsWeb;

  void tap() {
    if (_on) HapticFeedback.lightImpact();
  }

  void tick() {
    if (_on) HapticFeedback.selectionClick();
  }

  void success() {
    if (_on) HapticFeedback.mediumImpact();
  }

  void fail() {
    if (!_on) return;
    HapticFeedback.heavyImpact();
    Future<void>.delayed(const Duration(milliseconds: 120), HapticFeedback.heavyImpact);
  }

  void chaos() {
    if (_on) HapticFeedback.mediumImpact();
  }
}
