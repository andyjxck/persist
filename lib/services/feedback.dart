import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logic/soundtrack.dart';
import 'web_sound.dart';

/// Sound effects. Every file in assets/audio is synthesised by
/// tool/make_sounds.py for this game (no samples, no licences): a dry clock
/// escapement, a press click, a latch and a thud. On the web the soundtrack
/// is a driving loop synthesised live by the page (see [musicStart]); it
/// starts once per run and is never restarted by a new round. Native builds
/// keep the clock as their soundtrack. Every sound is preloaded into a small pool of
/// ready players, so nothing is created or decoded while you play. Every
/// call fails quietly, so a browser that blocks audio never breaks the game.
class GameAudio {
  bool _enabled = true;
  bool get enabled => _enabled;
  set enabled(bool on) {
    _enabled = on;
    if (kIsWeb) webMusicEnable(on);
  }
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
  static const glitch = 'glitch.wav';
  static const buzz = 'buzz.wav';

  static const files = [tick, tock, tickTight, tockTight, press, clear, fail, reveal, glitch, buzz];

  /// Players kept ready per sound: enough for the fastest overlap.
  static int poolSize(String file) => switch (file) {
    press => 4,
    tick || tock || tickTight || tockTight => 3,
    _ => 1,
  };

  Future<void> preload() async {
    if (_loaded) return;
    // The web plays through Web Audio in index.html (see web_sound.dart).
    if (kIsWeb) {
      _loaded = true;
      return;
    }
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
    if (kIsWeb) {
      webSoundPlay(file, volume);
      return;
    }
    final pool = _pools[file];
    if (pool == null) return; // not loaded (yet): stay silent rather than stall
    try {
      await pool.start(volume: volume);
    } catch (e) {
      debugPrint('Audio play failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Soundtrack
  // ---------------------------------------------------------------------------

  /// How many times the soundtrack has been started, and whether it is
  /// playing now. A run starts it once; nothing else may.
  int musicStarts = 0;
  int musicStops = 0;
  bool musicPlaying = false;
  bool musicDucked = false;
  SoundtrackMix? _lastMix;
  SoundtrackMix? get lastMix => _lastMix;

  /// Whether the soundtrack (not the clock) is what you hear.
  bool get hasMusic => kIsWeb && webMusicAvailable();

  /// Starts the soundtrack for a new run. Does nothing if it's already
  /// playing, so it can never jump back to the start mid-run.
  void musicStart() {
    if (musicPlaying) return;
    musicPlaying = true;
    musicDucked = false;
    musicStarts++;
    _lastMix = null;
    if (kIsWeb) webMusicStart();
  }

  /// Fades the soundtrack out for good (the run is over).
  void musicStop() {
    if (!musicPlaying) return;
    musicPlaying = false;
    musicDucked = false;
    musicStops++;
    if (kIsWeb) webMusicStop();
  }

  /// Drops the soundtrack to silence without stopping it (you've just
  /// lost), or brings it straight back where it was (TRY AGAIN).
  void musicDuck(bool down) {
    if (!musicPlaying || musicDucked == down) return;
    musicDucked = down;
    if (kIsWeb) webMusicDuck(down);
  }

  /// Tells the soundtrack how hard to push right now.
  void musicSet(SoundtrackMix mix) {
    if (!musicPlaying || mix.near(_lastMix)) return;
    _lastMix = mix;
    if (kIsWeb) webMusicSet(mix.bpm, mix.tier, mix.key, mix.urgency, mix.calm);
  }

  /// Seconds since the last beat of the soundtrack was heard, or -1.
  double musicBeatAge() => hasMusic && musicPlaying ? webMusicBeatAge() : -1;

  void playPress() => _play(press, 0.75);
  void playClear() => _play(clear, 0.6);
  void playFail() => _play(fail, 1.0);
  void playReveal() => _play(reveal, 0.9);

  /// Static: the lights cut out, or buttons jump places.
  void playGlitch() => _play(glitch, 0.7);

  /// The HURRY buzzer.
  void playBuzz() => _play(buzz, 0.55);

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
