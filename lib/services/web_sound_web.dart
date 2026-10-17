import 'dart:js_interop';

@JS('bpSound')
external JSObject? get _bpSound;

@JS('bpSound.play')
external void _play(String name, double volume);

@JS('bpSound.music')
external JSObject? get _music;

@JS('bpSound.music.start')
external void _musicStart();

@JS('bpSound.music.stop')
external void _musicStop();

@JS('bpSound.music.duck')
external void _musicDuck(bool down);

@JS('bpSound.music.enable')
external void _musicEnable(bool on);

@JS('bpSound.music.set')
external void _musicSet(double bpm, int tier, int key, double urgency, bool calm);

@JS('bpSound.music.beatAge')
external double _musicBeatAge();

/// Plays [file] (e.g. 'tick.wav') through the page's Web Audio player.
void webSoundPlay(String file, double volume) {
  try {
    if (_bpSound == null) return;
    _play(file.replaceAll('.wav', ''), volume);
  } catch (_) {}
}

/// Whether the page has the soundtrack player.
bool webMusicAvailable() {
  try {
    return _bpSound != null && _music != null;
  } catch (_) {
    return false;
  }
}

void webMusicStart() {
  try {
    if (webMusicAvailable()) _musicStart();
  } catch (_) {}
}

void webMusicStop() {
  try {
    if (webMusicAvailable()) _musicStop();
  } catch (_) {}
}

void webMusicDuck(bool down) {
  try {
    if (webMusicAvailable()) _musicDuck(down);
  } catch (_) {}
}

void webMusicEnable(bool on) {
  try {
    if (webMusicAvailable()) _musicEnable(on);
  } catch (_) {}
}

void webMusicSet(double bpm, int tier, int key, double urgency, bool calm) {
  try {
    if (webMusicAvailable()) _musicSet(bpm, tier, key, urgency, calm);
  } catch (_) {}
}

/// Seconds since the soundtrack's last beat was heard, or -1 when it isn't
/// playing.
double webMusicBeatAge() {
  try {
    if (!webMusicAvailable()) return -1;
    return _musicBeatAge();
  } catch (_) {
    return -1;
  }
}
