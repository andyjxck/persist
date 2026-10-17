// What the device can actually do (a mouse that hovers, a touch screen),
// read from the browser's media queries on the web. Used to pick between the
// desktop and phone versions by input, not by window size alone, so an iPad
// in landscape doesn't get keyboard rounds and a laptop doesn't get rounds
// that need two fingers.
export 'input_caps_stub.dart' if (dart.library.js_interop) 'input_caps_web.dart';
