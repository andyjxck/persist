/// Native builds: never used (flame_audio plays the sounds, and the clock
/// is the soundtrack).
void webSoundPlay(String file, double volume) {}
bool webMusicAvailable() => false;
void webMusicStart() {}
void webMusicStop() {}
void webMusicDuck(bool down) {}
void webMusicEnable(bool on) {}
void webMusicSet(double bpm, int tier, int key, double urgency, bool calm) {}
double webMusicBeatAge() => -1;
