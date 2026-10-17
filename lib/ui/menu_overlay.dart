import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import 'theme.dart';
import 'widgets.dart';

/// The start screen: a control panel at night. The big red button starts
/// today's Daily; scores sit on a readout; Endless and Story sit under it,
/// and the leaderboards when they're switched on. On the wide web stage it
/// is two columns (words left, button right); on a phone it stacks.
class MenuOverlay extends StatefulWidget {
  const MenuOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<MenuOverlay> {
  ButtonPanicGame get game => widget.game;

  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  String get _today {
    final d = game.clock();
    return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BP.ink,
      child: Stack(
        children: [
          const Positioned.fill(child: Halftone()),
          const Positioned.fill(child: _Vignette()),
          Column(
            children: [
              const HazardTape(height: 6),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: ListenableBuilder(
                    listenable: game.settingsRevision,
                    builder: (context, _) => Column(
                      children: [
                        _topBar(),
                        Expanded(
                          child: LayoutBuilder(builder: (context, box) => game.wide ? _wideBody(box) : _phoneBody(box)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const HazardTape(height: 6),
            ],
          ),
        ],
      ),
    );
  }

  // --- Pieces ----------------------------------------------------------------

  Widget _topBar() {
    final wide = game.wide;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? BP.s6 : BP.s4, BP.s1, wide ? BP.s5 : BP.s1, 0),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const StatusLamp(size: 7),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    wide ? 'PANEL 7  \u00b7  LIVE  \u00b7  $_today' : _today,
                    style: BP.label(11, color: BP.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (game.leaderboards.enabled && !wide)
            StarkAction(
              key: const Key('boardsChip'),
              look: ActionLook.chip,
              label: 'BOARDS',
              size: 10,
              color: BP.cream,
              semantic: 'Leaderboards',
              onTap: () => game.openPanel('leaderboard'),
            ),
          if (!kIsWeb)
            StarkAction(
              look: ActionLook.chip,
              label: 'BUZZ',
              lit: game.haptics.enabled,
              size: 10,
              color: BP.cream,
              semantic: game.haptics.enabled ? 'Vibration on' : 'Vibration off',
              onTap: () => game.setHaptics(!game.haptics.enabled),
            ),
          StarkAction(
            look: ActionLook.chip,
            label: game.audio.enabled ? 'SOUND' : 'MUTED',
            lit: game.audio.enabled,
            size: 10,
            color: BP.cream,
            semantic: game.audio.enabled ? 'Sound on' : 'Sound off',
            onTap: () => game.setSound(!game.audio.enabled),
          ),
        ],
      ),
    );
  }

  /// BUTTON / PANIC: bone white, then alarm red with a faint misregistered
  /// double behind it, like a screen that's starting to fail. Straight.
  Widget _title(double size, {bool left = false}) {
    return Semantics(
      header: true,
      label: 'Button Panic',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('BUTTON', style: BP.d(size, height: 0.92, spacing: size * 0.01)),
            Stack(
              children: [
                Transform.translate(
                  offset: Offset(size * 0.03, 0),
                  child: Text('PANIC', style: BP.d(size, color: BP.blood, height: 0.92, spacing: size * 0.01)),
                ),
                Text('PANIC', style: BP.d(size, color: BP.signal, height: 0.92, spacing: size * 0.01)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _eyebrow({required bool wide}) {
    final text = Text('SAME BUTTONS FOR EVERYONE TODAY', style: BP.label(wide ? 12 : 10, color: BP.muted));
    if (!wide) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: BP.hazard, width: 1.5), borderRadius: BorderRadius.circular(2)),
          child: Text('WARNING', style: BP.label(11, color: BP.hazard)),
        ),
        const SizedBox(width: BP.s3),
        text,
      ],
    );
  }

  Widget _tagline(double size, {TextAlign align = TextAlign.center}) =>
      Text('Read it. Then press. Or don\u2019t.', textAlign: align, style: BP.t(size, color: BP.muted, weight: FontWeight.w700, height: 1.25));

  /// Today's Daily (first and best) and the Endless best, on one ticket.
  Widget _ticket({required bool wide}) {
    final daily = game.store.dailyFor(game.clock(), variant: game.dailyVariant);
    final best = game.store.bestEndless;
    String show(int? v) => v == null || v <= 0 ? '\u2014' : '$v';
    final cells = [
      ('TODAY', show(daily?.firstScore)),
      ('DAILY BEST', show(daily?.bestScore)),
      ('ENDLESS BEST', show(best)),
    ];
    final valueSize = wide ? 32.0 : 24.0;
    Widget cell((String, String) c) => Padding(
      padding: EdgeInsets.symmetric(horizontal: wide ? BP.s4 + 2 : BP.s3, vertical: wide ? BP.s3 : BP.s2 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(c.$1, style: BP.label(wide ? 10.5 : 9.5, color: BP.onInk))),
          const SizedBox(height: 3),
          Text(c.$2, style: BP.d(valueSize, color: c.$2 == '\u2014' ? BP.faint : BP.paper)),
        ],
      ),
    );
    const rule = SizedBox(width: 1, child: ColoredBox(color: BP.line));
    return Semantics(
      label: 'Today ${cells[0].$2 == '\u2014' ? 'not played' : cells[0].$2}, daily best ${cells[1].$2}, endless best ${cells[2].$2}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: BP.panel,
            border: Border.all(color: BP.line, width: 1),
            borderRadius: BorderRadius.circular(BP.radius),
          ),
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) rule,
                  wide ? cell(cells[i]) : Expanded(child: cell(cells[i])),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dailyTag() {
    final played = game.store.dailyFor(game.clock(), variant: game.dailyVariant) != null;
    return Text(played ? 'PLAY TODAY\u2019S DAILY AGAIN' : 'START TODAY\u2019S DAILY', style: BP.label(12, color: BP.paper));
  }

  Widget _bigButton(double size) =>
      VoidButton(key: const Key('dailyButton'), size: size, semantic: 'Start the daily run', onTap: () => game.startRun(GameMode.daily));

  Widget _endless({required bool wide}) => StarkAction(
    key: const Key('endlessButton'),
    label: 'ENDLESS',
    size: wide ? 14 : 12,
    keyHint: wide ? 'E' : null,
    semantic: 'Play endless mode',
    onTap: () => game.startRun(GameMode.endless),
  );

  Widget _story({required bool wide}) {
    final cleared = game.store.storyCleared;
    return StarkAction(
      key: const Key('storyButton'),
      label: 'STORY',
      size: wide ? 14 : 12,
      keyHint: wide ? 'S' : null,
      semantic: cleared == 0 ? 'Story mode' : 'Story mode, $cleared shifts cleared',
      onTap: () => game.openPanel('story'),
    );
  }

  Widget _boards() => StarkAction(
    key: const Key('boardsButton'),
    label: 'BOARDS',
    size: 14,
    keyHint: 'L',
    semantic: 'Leaderboards',
    onTap: () => game.openPanel('leaderboard'),
  );

  /// The other actions in one row (wraps if it has to).
  Widget _actions({required bool wide}) => Wrap(
    alignment: wide ? WrapAlignment.start : WrapAlignment.center,
    children: [
      _endless(wide: wide),
      _story(wide: wide),
      if (wide && game.leaderboards.enabled) _boards(),
    ],
  );

  // --- Layouts ---------------------------------------------------------------

  Widget _wideBody(BoxConstraints box) {
    final w = box.maxWidth, h = box.maxHeight;
    final title = (w * 0.095).clamp(64.0, 150.0).clamp(0.0, h * 0.2).toDouble();
    final button = (h * 0.3).clamp(110.0, 210.0).clamp(0.0, w * 0.18).toDouble();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: BP.s7, vertical: BP.s5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _eyebrow(wide: true),
                  SizedBox(height: title * 0.22),
                  _title(title, left: true),
                  SizedBox(height: title * 0.24),
                  _tagline((title * 0.17).clamp(16.0, 24.0), align: TextAlign.left),
                  SizedBox(height: (title * 0.24).clamp(BP.s4, BP.s6)),
                  _ticket(wide: true),
                  SizedBox(height: (title * 0.2).clamp(BP.s4, BP.s5 + 4)),
                  _actions(wide: true),
                  const SizedBox(height: BP.s3),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: KeyHints([
                      ('SPACE', 'DAILY'),
                      ('E', 'ENDLESS'),
                      ('S', 'STORY'),
                      if (game.leaderboards.enabled) ('L', 'BOARDS'),
                      ('M', game.audio.enabled ? 'MUTE' : 'UNMUTE'),
                    ]),
                  ),
                ],
              ),
            ),
            SizedBox(width: (w * 0.09).clamp(BP.s6, 150.0)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bigButton(button),
                SizedBox(height: button * 0.14),
                _dailyTag(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneBody(BoxConstraints box) {
    final w = box.maxWidth, h = box.maxHeight;
    final title = (w * 0.2).clamp(52.0, 104.0).clamp(0.0, h * 0.115).toDouble();
    final button = (w * 0.34).clamp(84.0, 150.0).clamp(0.0, h * 0.2).toDouble();
    final tight = h < 620;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(BP.s4, tight ? BP.s2 : BP.s4, BP.s4, tight ? BP.s3 : BP.s5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _eyebrow(wide: false),
              SizedBox(height: tight ? BP.s2 : BP.s3),
              _title(title),
              SizedBox(height: tight ? BP.s2 : BP.s3),
              _tagline(tight ? 14 : 16),
              SizedBox(height: tight ? BP.s2 : BP.s5),
              _bigButton(button),
              SizedBox(height: tight ? BP.s1 : BP.s3),
              _dailyTag(),
              SizedBox(height: tight ? BP.s3 : BP.s5),
              _ticket(wide: false),
              SizedBox(height: tight ? BP.s2 : BP.s4),
              _actions(wide: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dark red bloom at the edges of the screen.
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(radius: 1.05, colors: [Color(0x00000000), Color(0x00000000), Color(0x40500A10)], stops: [0, 0.6, 1]),
      ),
    ),
  );
}
