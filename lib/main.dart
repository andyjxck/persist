import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp, ThemeData, Brightness;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'game/button_panic_game.dart';
import 'services/storage.dart';
import 'ui/stage.dart';
import 'ui/theme.dart';
import 'ui/web_page.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: BP.ink,
      ),
    );
  }
  final store = await ScoreStore.open();
  runApp(ButtonPanicApp(store: store));
}

/// Picks one of two standalone experiences:
///  * web on a big screen: a web page with the game on a stage in it,
///    mouse + keyboard, desktop-only rounds;
///  * phones (the app, or a phone browser): full screen, touch, haptics,
///    touch-only rounds.
class ButtonPanicApp extends StatefulWidget {
  const ButtonPanicApp({super.key, required this.store});
  final ScoreStore store;

  /// The web page needs at least this much room.
  static const wideMinWidth = 900.0;
  static const wideMinHeight = 560.0;

  @override
  State<ButtonPanicApp> createState() => _ButtonPanicAppState();
}

class _ButtonPanicAppState extends State<ButtonPanicApp> {
  late final ButtonPanicGame game = ButtonPanicGame(
    store: widget.store,
    // Hidden preview options only exist on the web link (see DemoConfig).
    demo: kIsWeb ? DemoConfig.fromUri(Uri.base) : const DemoConfig(),
  );
  final _gameKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Button Panic',
      debugShowCheckedModeBanner: false,
      color: BP.ink,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: BP.text, useMaterial3: true),
      home: LayoutBuilder(
        builder: (context, box) {
          final wide = kIsWeb && box.maxWidth >= ButtonPanicApp.wideMinWidth && box.maxHeight >= ButtonPanicApp.wideMinHeight;
          game.wide = wide;
          return DefaultTextStyle(
            style: BP.t(15),
            child: wide ? WebPage(game: game, gameKey: _gameKey) : _PhoneShell(game: game, gameKey: _gameKey),
          );
        },
      ),
    );
  }
}

/// The phone version: the game fills the screen inside the safe area, with
/// a mute button in the corner while you play.
class _PhoneShell extends StatefulWidget {
  const _PhoneShell({required this.game, required this.gameKey});
  final ButtonPanicGame game;
  final GlobalKey gameKey;

  @override
  State<_PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<_PhoneShell> {
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return ColoredBox(
      color: BP.ink,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: GameStage(game: game, gameKey: widget.gameKey)),
            ValueListenableBuilder<int>(
              valueListenable: game.revision,
              builder: (context, _, _) {
                final inPlay = game.phase != GamePhase.menu && game.phase != GamePhase.gameOver && game.phase != GamePhase.fakeGameOver;
                if (!inPlay) return const SizedBox.shrink();
                return Positioned(
                  top: 6,
                  right: 12,
                  child: IconPill(
                    semantic: 'Sound',
                    painter: SpeakerPainter(game.audio.enabled),
                    onTap: () => setState(() => game.setSound(!game.audio.enabled)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
