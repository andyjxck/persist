import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import 'stage.dart';
import 'theme.dart';
import 'widgets.dart';

/// The web version: a real web page (header, hero, the game on a stage in
/// the page, how to play, the rounds, your numbers, footer), played with
/// mouse and keyboard.
class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.game, required this.gameKey});
  final ButtonPanicGame game;
  final GlobalKey gameKey;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  ButtonPanicGame get game => widget.game;
  final _scroll = ScrollController();
  final _playKey = GlobalKey();
  final _howKey = GlobalKey();
  final _roundsKey = GlobalKey();
  final _scoresKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'page');

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _goTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic, alignment: 0.05);
    }
  }

  void _toggleSound() => setState(() => game.setSound(!game.audio.enabled));

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final label = k == LogicalKeyboardKey.space ? 'Space' : k.keyLabel;
    switch (game.phase) {
      case GamePhase.playing:
      case GamePhase.roundWon:
      case GamePhase.failing:
      case GamePhase.fakeGameOver:
        // Every key is part of the game while playing (some rounds are traps).
        game.keyDown(label);
        return KeyEventResult.handled;
      case GamePhase.menu:
        if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
          _goTo(_playKey);
          game.startRun(GameMode.daily);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.keyE) {
          _goTo(_playKey);
          game.startRun(GameMode.endless);
          return KeyEventResult.handled;
        }
      case GamePhase.gameOver:
        if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.keyR) {
          game.startRun(game.lastResult?.mode ?? GameMode.endless);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.escape) {
          game.backToMenu();
          return KeyEventResult.handled;
        }
    }
    if (k == LogicalKeyboardKey.keyM) {
      _toggleSound();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: BP.ink,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return Column(
              children: [
                _header(w),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      children: [
                        _hero(w, box.maxHeight),
                        _section(_howKey, _howToPlay(w)),
                        _section(_roundsKey, _rounds(w)),
                        _section(_scoresKey, _scores(w)),
                        _footer(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _contained(Widget child, {double vertical = 0}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1240),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: 40, vertical: vertical), child: child),
    ),
  );

  Widget _section(Key key, Widget child) => Container(
    key: key,
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: BP.line))),
    child: _contained(child, vertical: 88),
  );

  // --- Header ------------------------------------------------------------------

  Widget _header(double w) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: BP.ink,
        border: Border(bottom: BorderSide(color: BP.line)),
      ),
      child: _contained(
        Row(
          children: [
            const LogoMark(size: 30),
            const SizedBox(width: 12),
            Text('Button Panic', style: BP.d(17, spacing: -0.2)),
            const SizedBox(width: 48),
            if (w > 1000) ...[
              _NavLink('Play', () => _goTo(_playKey)),
              _NavLink('How to play', () => _goTo(_howKey)),
              _NavLink('Rounds', () => _goTo(_roundsKey)),
              _NavLink('Your scores', () => _goTo(_scoresKey)),
            ],
            const Spacer(),
            IconPill(
              semantic: 'Sound',
              painter: SpeakerPainter(game.audio.enabled),
              label: game.audio.enabled ? 'Sound on' : 'Muted',
              onTap: _toggleSound,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: TactileButton(
                label: 'PLAY NOW',
                compact: true,
                height: 42,
                onTap: () {
                  _goTo(_playKey);
                  if (game.phase == GamePhase.menu) game.startRun(GameMode.daily);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Hero: intro + the stage -----------------------------------------------

  Widget _hero(double w, double h) {
    final stacked = w < 1180;
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('A STRESS TEST WITH ONE BUTTON', style: BP.label(12, color: BP.signal)),
        const SizedBox(height: BP.s4),
        Text('One button.\nZero mercy.', style: BP.d(stacked ? 48 : 54, height: 1.02, spacing: -1.5)),
        const SizedBox(height: BP.s4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Press it. Don\'t press it. Press the red one, which isn\'t red. Every round is a new trick, '
            'and the ring around the button is your clock.',
            style: BP.t(17, color: BP.muted),
          ),
        ),
        const SizedBox(height: BP.s5),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Kbd('Space'),
            Text('start', style: BP.t(13, color: BP.muted)),
            const SizedBox(width: 6),
            const Kbd('Esc'),
            Text('menu', style: BP.t(13, color: BP.muted)),
            const SizedBox(width: 6),
            const Kbd('M'),
            Text('mute', style: BP.t(13, color: BP.muted)),
          ],
        ),
        const SizedBox(height: BP.s6),
        ValueListenableBuilder<int>(valueListenable: game.revision, builder: (context, _, _) => _dailyCard()),
      ],
    );
    final stageH = (h - 72 - 96).clamp(460.0, 680.0);
    final stage = _stageCard(stageH);
    return Container(
      key: _playKey,
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0.5, -0.6), radius: 1.2, colors: [Color(0xFF1A1420), BP.ink]),
      ),
      child: _contained(
        stacked
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [intro, const SizedBox(height: BP.s6), stage])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 380, child: intro),
                  const SizedBox(width: 48),
                  Expanded(child: stage),
                ],
              ),
        vertical: 48,
      ),
    );
  }

  Widget _stageCard(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: BP.line),
        boxShadow: const [
          BoxShadow(color: Color(0xAA000000), blurRadius: 60, offset: Offset(0, 30)),
          BoxShadow(color: Color(0x22FF3B4E), blurRadius: 120, spreadRadius: -40),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: GameStage(game: game, gameKey: widget.gameKey),
      ),
    );
  }

  Widget _dailyCard() {
    final today = game.clock();
    final daily = game.store.dailyFor(today);
    return Container(
      padding: const EdgeInsets.all(BP.s5),
      decoration: BoxDecoration(color: BP.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: BP.line)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TODAY\'S DAILY', style: BP.label(10.5)),
                const SizedBox(height: 6),
                Text(prettyDate(today), style: BP.d(18, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  daily == null ? 'Same rounds for everyone on the web today.' : 'First try ${daily.firstScore} · best ${daily.bestScore}',
                  style: BP.t(13, color: BP.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: BP.s3),
          _bigNumber(daily == null ? '–' : '${daily.firstScore}', 'SCORE'),
        ],
      ),
    );
  }

  Widget _bigNumber(String n, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(n, style: BP.d(36, height: 1)),
      const SizedBox(height: 4),
      Text(label, style: BP.label(9.5, color: BP.faint)),
    ],
  );

  // --- How to play -------------------------------------------------------------

  Widget _sectionTitle(String eyebrow, String title, String body) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(eyebrow, style: BP.label(12, color: BP.signal)),
      const SizedBox(height: BP.s3),
      Text(title, style: BP.d(38, spacing: -1, height: 1.1)),
      const SizedBox(height: BP.s3),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: Text(body, style: BP.t(17, color: BP.muted))),
      const SizedBox(height: BP.s6),
    ],
  );

  Widget _howToPlay(double w) {
    final steps = [
      ('01', 'Read it', 'Every round gives you one instruction. Some are honest.', const RingGlyph(size: 44, fraction: 1, color: BP.faint)),
      ('02', 'Beat the ring', 'The ring around the button is the clock. It drains, turns amber, then red, and ticks faster.', const RingGlyph(size: 44, fraction: 0.35, color: BP.amber)),
      ('03', 'Trust nothing', 'Labels lie, the screen fakes a win, buttons swap places. One wrong press ends the run.', const RingGlyph(size: 44, fraction: 0.6, color: BP.paper, button: Color(0xFF3D7BFF))),
      ('04', 'Come back tomorrow', 'The Daily is the same run for everyone. Your first try is your score.', const RingGlyph(size: 44, fraction: 0.85, color: BP.mint, button: Color(0xFF22C77A))),
    ];
    final cols = w > 1100 ? 4 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('HOW TO PLAY', 'Simple rules. Rude game.', 'Click the button with your mouse, or use your keyboard when it asks. Rounds get faster and stranger the longer you last.'),
        _grid(cols, [
          for (final s in steps)
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [s.$4, const Spacer(), Text(s.$1, style: BP.d(14, color: BP.faint))]),
                  const SizedBox(height: BP.s5),
                  Text(s.$2, style: BP.d(20, weight: FontWeight.w600)),
                  const SizedBox(height: BP.s2),
                  Text(s.$3, style: BP.t(14.5, color: BP.muted)),
                ],
              ),
            ),
        ]),
      ],
    );
  }

  Widget _grid(int cols, List<Widget> children, {double gap = 20}) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, (i + cols).clamp(0, children.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) SizedBox(width: gap),
                Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
              ],
            ],
          ),
        ),
      );
      if (i + cols < children.length) rows.add(SizedBox(height: gap));
    }
    return Column(children: rows);
  }

  // --- Rounds ----------------------------------------------------------------

  static const _roundList = [
    ('Press it', 'Exactly what it says. Usually.', false),
    ('Don\'t press it', 'The hardest thing is doing nothing.', false),
    ('Press it N times', 'Count out loud. Don\'t go over.', false),
    ('Hold it', 'Hold, and let go at the right moment.', false),
    ('Liar', 'The label says RED. The button is blue.', false),
    ('Memory', 'What colour was it three rounds ago?', false),
    ('Runner', 'It shrinks, it dodges, it moves.', false),
    ('Fakes', 'Fake loading, fake wins, fake notifications.', false),
    ('Catch it', 'The button runs from your cursor across the whole stage.', true),
    ('Key traps', 'Press F on your keyboard. Or click, and don\'t touch a key.', true),
    ('Hover, don\'t click', 'Rest the cursor on it. Your finger will want to click.', true),
    ('Magnet', 'It follows your cursor. Don\'t let it touch.', true),
    ('The wall', 'Twenty-one buttons. Press every green one, or find the odd one out.', true),
  ];

  Widget _rounds(double w) {
    final cols = w > 1100 ? 3 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'ROUNDS',
          'Every round is a different trick.',
          'Shared rounds work everywhere. The web version adds rounds built for a mouse, a keyboard and a wide screen. '
              'On a phone you get touch-only rounds instead: flick it, hold it with two thumbs, rub it clean.',
        ),
        _grid(cols, [
          for (final r in _roundList)
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(r.$1, style: BP.d(18, weight: FontWeight.w600))),
                      if (r.$3)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: BP.signal.withValues(alpha: 0.14)),
                          child: Text('WEB ONLY', style: BP.label(9, color: BP.signal)),
                        ),
                    ],
                  ),
                  const SizedBox(height: BP.s2),
                  Text(r.$2, style: BP.t(14.5, color: BP.muted)),
                ],
              ),
            ),
        ], gap: 16),
      ],
    );
  }

  // --- Scores ----------------------------------------------------------------

  Widget _scores(double w) {
    return ValueListenableBuilder<int>(
      valueListenable: game.revision,
      builder: (context, _, _) {
        final today = game.clock();
        final daily = game.store.dailyFor(today);
        final stats = [
          ('BEST ENDLESS', '${game.store.bestEndless}', 'rounds'),
          ('TODAY\'S DAILY', daily == null ? '–' : '${daily.firstScore}', daily == null ? 'not played yet' : 'first try'),
          ('DAILY BEST', daily == null ? '–' : '${daily.bestScore}', 'today, any try'),
          ('RUNS PLAYED', '${game.store.runsPlayed}', 'on this browser'),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('YOUR SCORES', 'The numbers don\'t lie. The button does.', 'Saved in this browser only. No accounts, no tracking.'),
            _grid(w > 1100 ? 4 : 2, [
              for (final s in stats)
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1, style: BP.label(10.5)),
                      const SizedBox(height: BP.s4),
                      Text(s.$2, style: BP.d(52, height: 1, spacing: -2)),
                      const SizedBox(height: BP.s2),
                      Text(s.$3, style: BP.t(13.5, color: BP.muted)),
                    ],
                  ),
                ),
            ]),
          ],
        );
      },
    );
  }

  // --- Footer ----------------------------------------------------------------

  Widget _footer() {
    return Container(
      decoration: const BoxDecoration(color: BP.ink2, border: Border(top: BorderSide(color: BP.line))),
      child: _contained(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LogoMark(size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Button Panic', style: BP.d(15)),
                  const SizedBox(height: 6),
                  Text('Made with Flutter and Flame. Better on a phone? There\'s a touch version with its own rounds.', style: BP.t(13.5, color: BP.muted)),
                ],
              ),
            ),
            const SizedBox(width: 40),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Type: Unbounded & Manrope (SIL Open Font License)', style: BP.t(12.5, color: BP.faint)),
                const SizedBox(height: 4),
                Text('Every sound synthesised for this game', style: BP.t(12.5, color: BP.faint)),
                const SizedBox(height: 4),
                SelectableText('github.com/andyjxck/persist', style: BP.t(12.5, color: BP.muted, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
        vertical: 40,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(BP.s5),
    decoration: BoxDecoration(color: BP.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: BP.line)),
    child: child,
  );
}

class _NavLink extends StatefulWidget {
  const _NavLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label, style: BP.t(14.5, color: _hover ? BP.paper : BP.muted, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 2,
                width: _hover ? 18 : 0,
                decoration: BoxDecoration(color: BP.signal, borderRadius: BorderRadius.circular(1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
