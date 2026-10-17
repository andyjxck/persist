import 'dart:js_interop';

@JS('window.matchMedia')
external _MediaQueryList _matchMedia(JSString query);

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

bool _query(String q, {required bool fallback}) {
  try {
    return _matchMedia(q.toJS).matches;
  } catch (_) {
    return fallback;
  }
}

/// True when the main pointer is a mouse or trackpad that can hover
/// (laptops, desktops). False on phones and tablets, even big ones.
bool inputHasMouse() => _query('(hover: hover) and (pointer: fine)', fallback: true);

/// True when any pointer is a finger (phones, tablets, touch laptops).
bool inputHasTouch() => _query('(any-pointer: coarse)', fallback: true);
