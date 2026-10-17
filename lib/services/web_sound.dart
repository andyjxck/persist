// Sound on the web goes through a tiny Web Audio player in web/index.html
// (window.bpSound), unlocked by the first touch, click or key press. HTML
// audio elements (what flame_audio uses on the web) are blocked or delayed
// by mobile browsers, which is why the web build was silent on phones.
export 'web_sound_stub.dart' if (dart.library.js_interop) 'web_sound_web.dart';
