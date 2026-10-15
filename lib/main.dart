import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/button_panic_game.dart';
import 'services/storage.dart';
import 'ui/game_over_overlay.dart';
import 'ui/menu_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = await ScoreStore.open();
  runApp(ButtonPanicApp(store: store));
}

class ButtonPanicApp extends StatefulWidget {
  const ButtonPanicApp({super.key, required this.store});
  final ScoreStore store;

  @override
  State<ButtonPanicApp> createState() => _ButtonPanicAppState();
}

class _ButtonPanicAppState extends State<ButtonPanicApp> {
  late final ButtonPanicGame game = ButtonPanicGame(
    store: widget.store,
    // Hidden preview options only exist on the web link (see DemoConfig).
    demo: kIsWeb ? DemoConfig.fromUri(Uri.base) : const DemoConfig(),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Button Panic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE53935), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF111117),
        body: SafeArea(
          // Raw pointer events: no gesture delays, reliable holds and fast taps.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => game.pointerDown(e.pointer, e.localPosition),
            onPointerUp: (e) => game.pointerUp(e.pointer),
            onPointerCancel: (e) => game.pointerUp(e.pointer),
            child: GameWidget<ButtonPanicGame>(
              game: game,
              overlayBuilderMap: {
                'menu': (context, game) => MenuOverlay(game: game),
                'gameOver': (context, game) => GameOverOverlay(game: game),
              },
              initialActiveOverlays: const ['menu'],
            ),
          ),
        ),
      ),
    );
  }
}
