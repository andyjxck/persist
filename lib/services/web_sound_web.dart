import 'dart:js_interop';

@JS('bpSound')
external JSObject? get _bpSound;

@JS('bpSound.play')
external void _play(String name, double volume);

/// Plays [file] (e.g. 'tick.wav') through the page's Web Audio player.
void webSoundPlay(String file, double volume) {
  try {
    if (_bpSound == null) return;
    _play(file.replaceAll('.wav', ''), volume);
  } catch (_) {}
}
