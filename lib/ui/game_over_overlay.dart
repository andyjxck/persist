import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import '../logic/story.dart';
import 'leaderboard_overlay.dart';
import 'theme.dart';
import 'widgets.dart';

/// The game-over screen: an incident report on a dark, red-lit screen. Story
/// runs get a shift report instead (failed or cleared). The surprise TRY AGAIN shows this exact screen for
/// a moment first, so it must not look any different: the buttons just
/// don't respond while the game is in its fake phase.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> with SingleTickerProviderStateMixin {
  ButtonPanicGame get game => widget.game;
  bool get _live => game.phase == GamePhase.gameOver;
  bool _copied = false;

  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _share(RunResult result) async {
    final text = result.shareText;
    var shared = false;
    if (!kIsWeb) {
      try {
        final r = await SharePlus.instance.share(ShareParams(text: text));
        shared = r.status != ShareResultStatus.unavailable;
      } catch (_) {}
    }
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final result = game.lastResult;
    if (result == null) return const SizedBox.shrink();
    final wide = game.wide;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enter = CurvedAnimation(parent: _in, curve: const Interval(0.3, 1, curve: Curves.easeOutCubic));

    Widget card = Stack(
      clipBehavior: Clip.none,
      children: [
        _card(result, wide),
        if (result.isNewBest || result.firstClear)
          Positioned(
            top: wide ? -16 : -14,
            right: wide ? 18 : 12,
            child: still
                ? Sticker(label: result.firstClear ? 'FIRST CLEAR' : 'NEW BEST', size: wide ? 22 : 18)
                : FadeTransition(
                    opacity: CurvedAnimation(parent: _in, curve: const Interval(0.6, 1)),
                    child: Sticker(label: result.firstClear ? 'FIRST CLEAR' : 'NEW BEST', size: wide ? 22 : 18),
                  ),
          ),
      ],
    );
    if (!still) {
      card = SlideTransition(position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(enter), child: card);
    }

    return FadeTransition(
      opacity: CurvedAnimation(parent: _in, curve: const Interval(0.3, 1)),
      child: ColoredBox(
        color: BP.ink,
        child: Stack(
          children: [
            Positioned.fill(child: _Bloom(color: result.cleared ? BP.hazard : BP.signal)),
            const Positioned.fill(child: Halftone()),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(BP.s5, BP.s6, BP.s5, BP.s5),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 580 : 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        card,
                        SizedBox(height: wide ? BP.s6 : BP.s5),
                        if (game.leaderboards.enabled && result.mode != GameMode.story && !result.practice) ...[
                          BoardStatus(game: game, live: _live),
                          SizedBox(height: wide ? BP.s5 : BP.s4),
                        ],
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: BP.s2,
                          runSpacing: BP.s2,
                          children: _actions(result, wide),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(RunResult result, bool wide) {
    final story = result.mode == GameMode.story;
    final lv = result.level;
    final last = lv != null && lv.number >= storyLevels.length;
    final mainLabel = !story
        ? 'AGAIN'
        : result.cleared
        ? (last ? 'REPLAY' : 'NEXT SHIFT')
        : 'RETRY';
    return [
      StarkAction(
        key: const Key('againButton'),
        look: ActionLook.primary,
        label: mainLabel,
        keyHint: wide ? 'SPACE' : null,
        semantic: story ? (result.cleared && !last ? 'Next shift' : 'Play this shift again') : 'Play again',
        size: 15,
        onTap: () => _live ? game.again() : null,
      ),
      if (story)
        StarkAction(
          key: const Key('shiftsButton'),
          label: 'SHIFTS',
          semantic: 'All shifts',
          size: 15,
          onTap: () => _live ? game.openPanel('story') : null,
        )
      else
        StarkAction(
          key: const Key('shareButton'),
          label: _copied ? 'COPIED' : (kIsWeb ? 'COPY' : 'SHARE'),
          semantic: _copied ? 'Copied' : (kIsWeb ? 'Copy result' : 'Share result'),
          size: 15,
          onTap: () => _live ? _share(result) : null,
        ),
      StarkAction(
        label: 'MENU',
        keyHint: wide ? 'ESC' : null,
        semantic: 'Menu',
        size: 15,
        onTap: () => _live ? game.backToMenu() : null,
      ),
    ];
  }

  /// The incident report: what got you, how far you got, how it compares.
  Widget _card(RunResult result, bool wide) {
    if (result.mode == GameMode.story && result.cleared) return _clearedCard(result, wide);
    final daily = result.mode == GameMode.daily;
    final d = result.date;
    final story = result.mode == GameMode.story;
    final lv = result.level;
    final modeLine = story && lv != null
        ? 'SHIFT ${lv.number.toString().padLeft(2, '0')}  \u00b7  ${lv.title}'
        : result.practice
        ? 'PRACTICE'
        : daily
        ? 'DAILY  \u00b7  ${d.day} ${_months[d.month - 1]}'
        : 'ENDLESS';
    final pad = wide ? BP.s6 - 4 : BP.s4 + 2;
    return Container(
      decoration: _cardDecoration(BP.signal),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BP.line))),
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
            child: Row(
              children: [
                Text(story ? 'SHIFT FAILED' : 'INCIDENT REPORT', style: BP.label(wide ? 12 : 11, color: BP.signal)),
                const SizedBox(width: BP.s3),
                Expanded(
                  child: Text(modeLine, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: BP.label(wide ? 11 : 10, color: BP.onInk)),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, wide ? BP.s5 : BP.s4, pad, wide ? BP.s5 : BP.s4),
            child: LayoutBuilder(
              builder: (context, box) {
                final scoreText = story && lv != null ? '${result.score}/${lv.length}' : '${result.score}';
                final wideScore = scoreText.length >= 3;
                final scoreSize = (wide ? 150.0 : 120.0).clamp(0.0, box.maxWidth * (scoreText.length >= 4 ? 0.3 : (wideScore ? 0.4 : 0.48))).toDouble();
                final unit = (scoreSize * 0.2).clamp(20.0, 30.0).toDouble();
                final items = <Widget>[
                  if (story && lv != null)
                    _stat('ATTEMPT', '${game.store.storyAttempts(lv.number)}')
                  else if (result.practice)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: BP.paper.withValues(alpha: 0.5), width: 1.5), borderRadius: BorderRadius.circular(2)),
                      child: Text(wide ? 'PRACTICE\nNOT SAVED' : 'PRACTICE  \u00b7  NOT SAVED', textAlign: TextAlign.center, style: BP.label(11, color: BP.paper)),
                    )
                  else ...[
                    _stat(daily ? 'DAILY BEST' : 'ENDLESS BEST', '${result.best}', hot: result.isNewBest),
                    if (daily && result.dailyFirst != null) _stat('FIRST TRY TODAY', '${result.dailyFirst}'),
                  ],
                ];
                final Widget stats = wide
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: BP.s2), items[i]],
                        ],
                      )
                    : Wrap(spacing: BP.s5, runSpacing: BP.s2, crossAxisAlignment: WrapCrossAlignment.center, children: items);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CAUSE', style: BP.label(10.5, color: BP.onInk)),
                    const SizedBox(height: 4),
                    Text(
                      result.reason.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BP.d(wide ? 40 : 30, color: BP.signal, spacing: 0.5, height: 1.02),
                    ),
                    SizedBox(height: wide ? BP.s4 : BP.s3),
                    const _DashedRule(),
                    SizedBox(height: wide ? BP.s3 : BP.s2),
                    Semantics(
                      label: '${result.score} ${result.score == 1 ? 'round' : 'rounds'} survived',
                      child: ExcludeSemantics(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(scoreText, style: BP.d(scoreSize, color: BP.cream, height: 0.92)),
                            SizedBox(width: wide ? BP.s4 : BP.s3),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: scoreSize * 0.08),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(result.score == 1 ? 'ROUND' : 'ROUNDS', style: BP.d(unit, height: 1)),
                                    Text('SURVIVED', style: BP.d(unit, color: BP.faint, height: 1)),
                                  ],
                                ),
                              ),
                            ),
                            if (wide)
                              Padding(
                                padding: EdgeInsets.only(bottom: scoreSize * 0.08, left: BP.s4),
                                child: stats,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (!wide) ...[
                      const SizedBox(height: BP.s3),
                      const SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: BP.line)),
                      const SizedBox(height: BP.s3),
                      stats,
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Dark, square-cornered card with a coloured top edge.
  static BoxDecoration _cardDecoration(Color edge) => BoxDecoration(
    color: BP.panel,
    border: Border(
      top: BorderSide(color: edge, width: 4),
      left: const BorderSide(color: BP.line),
      right: const BorderSide(color: BP.line),
      bottom: const BorderSide(color: BP.line),
    ),
    // Square corners: Flutter can't round a border whose sides differ in
    // colour (the top edge is the signal colour).
    boxShadow: [BoxShadow(color: edge.withValues(alpha: 0.18), blurRadius: 40)],
  );

  /// A cleared Story shift: the log line, and what comes next.
  Widget _clearedCard(RunResult result, bool wide) {
    final lv = result.level!;
    final next = storyLevel(lv.number + 1);
    final pad = wide ? BP.s6 - 4 : BP.s4 + 2;
    return Container(
      decoration: _cardDecoration(BP.hazard),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BP.line))),
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
            child: Row(
              children: [
                Text('SHIFT LOG', style: BP.label(wide ? 12 : 11, color: BP.hazard)),
                const SizedBox(width: BP.s3),
                Expanded(
                  child: Text(
                    'SHIFT ${lv.number.toString().padLeft(2, '0')}  \u00b7  ${lv.title}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BP.label(wide ? 11 : 10, color: BP.onInk),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, wide ? BP.s5 : BP.s4, pad, wide ? BP.s5 : BP.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text('SURVIVED', style: BP.d(wide ? 96 : 64, color: BP.cream, height: 0.95)),
                ),
                const SizedBox(height: BP.s2),
                Text(result.reason, style: BP.t(wide ? 17 : 15, color: BP.muted, weight: FontWeight.w600)),
                SizedBox(height: wide ? BP.s4 : BP.s3),
                const _DashedRule(),
                SizedBox(height: wide ? BP.s3 : BP.s2),
                Wrap(
                  spacing: BP.s5,
                  runSpacing: BP.s2,
                  children: [
                    _stat('ROUNDS', '${result.score}/${lv.length}'),
                    _stat('ATTEMPTS', '${game.store.storyAttempts(lv.number)}'),
                  ],
                ),
                const SizedBox(height: BP.s3),
                Text(
                  next == null ? 'THAT WAS THE LAST SHIFT.' : 'NEXT: SHIFT ${next.number.toString().padLeft(2, '0')}  \u00b7  ${next.title}',
                  style: BP.label(11, color: next == null ? BP.hazard : BP.onInk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool hot = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(label, style: BP.label(11, color: BP.onInk)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        color: hot ? BP.hazard : null,
        child: Text(value, style: BP.d(22, color: hot ? BP.ink : BP.paper, height: 1.1)),
      ),
    ],
  );
}

/// A glow of [color] rising from the bottom of a dark screen.
class _Bloom extends StatelessWidget {
  const _Bloom({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, 1.1),
          radius: 1.3,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.08), const Color(0x00000000)],
          stops: const [0, 0.45, 1],
        ),
      ),
    ),
  );
}

/// A dashed hairline, like a tear-off line.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 2, width: double.infinity, child: CustomPaint(painter: _DashPainter()));
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = BP.faint;
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 7, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}
