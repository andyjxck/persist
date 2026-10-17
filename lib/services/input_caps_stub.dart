/// Native builds (and tests): the app is the phone version, so these only
/// matter on the web. A mouse is assumed so wide-layout tests keep working.
bool inputHasMouse() => true;

/// Native builds: a phone, so yes.
bool inputHasTouch() => true;
