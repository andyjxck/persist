import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound effects and music. Every file in assets/audio is synthesised by
/// tool/make_sounds.py for this game (no samples, no licences), tuned to one
/// key and level-matched. Volumes below are the final mix. Every call fails
/// quietly, so a browser that blocks audio never breaks the game.
class GameAudio {
  bool enabled = true;
  AudioPlayer? _music;
  double _tempo = 1;
  bool _loaded = false;
  final Map<String, AudioPool> _pools = {};

  static const tap = 'tap.wav';
  static const success = 'success.wav';
  static const fail = 'fail.wav';
  static const reveal = 'reveal.wav';
  static const tick = 'tick.wav';
  static const tickHi = 'tick_hi.wav';
  static const pop = 'pop.wav';
  static const whoosh = 'whoosh.wav';
  static const music = 'loop.wav';

  static const _musicVolume = 0.32;

  Future<void> preload() async {
    if (_loaded) return;
    try {
      await FlameAudio.audioCache.loadAll([tap, success, fail, reveal, tick, tickHi, pop, whoosh, music]);
      // Pools for the sounds that fire fast and overlap.
      for (final f in [tap, tick, tickHi, pop]) {
        _pools[f] = await FlameAudio.createPool(f, maxPlayers: f == tap ? 4 : 3);
      }
      _loaded = true;
    } catch (e) {
      debugPrint('Audio preload failed: $e');
    }
  }

  Future<void> _play(String file, double volume) async {
    if (!enabled) return;
    try {
      final pool = _pools[file];
      if (pool != null) {
        await pool.start(volume: volume);
      } else {
        await FlameAudio.play(file, volume: volume);
      }
    } catch (e) {
      debugPrint('Audio play failed: $e');
    }
  }

  void playTap() => _play(tap, 0.7);
  void playSuccess() => _play(success, 0.75);
  void playFail() {
    _play(fail, 0.9);
    _duck();
  }

  void playReveal() => _play(reveal, 0.85);
  void playTick({bool urgent = false}) => urgent ? _play(tickHi, 0.75) : _play(tick, 0.6);
  void playPop() => _play(pop, 0.45);
  void playWhoosh() => _play(whoosh, 0.5);

  Future<void> _duck() async {
    try {
      await _music?.setVolume(_musicVolume * 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _music?.setVolume(_musicVolume);
    } catch (_) {}
  }

  Future<void> startMusic() async {
    if (!enabled || _music != null) return;
    try {
      _music = await FlameAudio.loop(music, volume: _musicVolume);
      await _music?.setPlaybackRate(_tempo);
    } catch (e) {
      debugPrint('Music failed: $e');
    }
  }

  /// Music speeds up as the run goes on.
  Future<void> setTempo(double tempo) async {
    _tempo = tempo;
    try {
      await _music?.setPlaybackRate(tempo);
    } catch (_) {}
  }

  Future<void> stopMusic() async {
    final m = _music;
    _music = null;
    try {
      await m?.stop();
      await m?.dispose();
    } catch (_) {}
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
