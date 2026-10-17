import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';
import 'theme.dart';
import 'widgets.dart';

/// The game-over screen. The surprise TRY AGAIN shows this exact screen for
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
        if (result.isNewBest)
          Positioned(
            top: wide ? -22 : -18,
            right: wide ? -14 : -6,
            child: still
                ? Sticker(label: 'NEW BEST!', size: wide ? 26 : 21, angle: 0.1)
                : ScaleTransition(
                    scale: CurvedAnimation(parent: _in, curve: const Interval(0.55, 1, curve: Curves.easeOutBack)),
                    child: Sticker(label: 'NEW BEST!', size: wide ? 26 : 21, angle: 0.1),
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
        color: BP.signal,
        child: Stack(
          children: [
            const Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _StripesPainter())))),
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
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: BP.s2,
                          runSpacing: BP.s2,
                          children: [
                            StarkAction(
                              key: const Key('againButton'),
                              look: ActionLook.hazard,
                              label: 'AGAIN',
                              keyHint: wide ? 'SPACE' : null,
                              semantic: 'Play again',
                              size: 15,
                              onTap: () => _live ? game.startRun(result.mode) : null,
                            ),
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
                          ],
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

  /// The incident report: what got you, how far you got, how it compares.
  Widget _card(RunResult result, bool wide) {
    final daily = result.mode == GameMode.daily;
    final d = result.date;
    final modeLine = result.practice
        ? 'PRACTICE'
        : daily
        ? 'DAILY  \u00b7  ${d.day} ${_months[d.month - 1]}'
        : 'ENDLESS';
    final pad = wide ? BP.s6 - 4 : BP.s4 + 2;
    return Container(
      decoration: BoxDecoration(
        color: BP.cream,
        border: Border.all(color: BP.paper, width: 3),
        borderRadius: BorderRadius.circular(BP.radius),
        boxShadow: const [BoxShadow(color: BP.paper, offset: Offset(8, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: BP.paper,
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
            child: Row(
              children: [
                Text('INCIDENT REPORT', style: BP.label(wide ? 12 : 11, color: BP.hazard)),
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
                final scoreSize = (wide ? 156.0 : 124.0).clamp(0.0, box.maxWidth * (result.score >= 100 ? 0.4 : 0.48)).toDouble();
                final unit = (scoreSize * 0.2).clamp(20.0, 30.0).toDouble();
                final items = <Widget>[
                  if (result.practice)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: BP.paper, width: 2), borderRadius: BorderRadius.circular(4)),
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
                    Text('CAUSE', style: BP.label(10.5, color: BP.muted)),
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
                            Stack(
                              children: [
                                Transform.translate(
                                  offset: Offset(scoreSize * 0.04, scoreSize * 0.04),
                                  child: Text('${result.score}', style: BP.d(scoreSize, color: BP.signal, height: 0.92)),
                                ),
                                Text('${result.score}', style: BP.d(scoreSize, height: 0.92)),
                              ],
                            ),
                            SizedBox(width: wide ? BP.s4 : BP.s3),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: scoreSize * 0.08),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(result.score == 1 ? 'ROUND' : 'ROUNDS', style: BP.d(unit, height: 1)),
                                    Text('SURVIVED', style: BP.d(unit, color: BP.muted, height: 1)),
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
                      const SizedBox(height: 2, width: double.infinity, child: ColoredBox(color: BP.paper)),
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

  Widget _stat(String label, String value, {bool hot = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(label, style: BP.label(11, color: BP.muted)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        color: hot ? BP.hazard : null,
        child: Text(value, style: BP.d(22, height: 1.1)),
      ),
    ],
  );
}

/// Faint deeper-red diagonal stripes behind the report.
class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const band = 34.0;
    final p = Paint()..color = BP.blood.withValues(alpha: 0.35);
    final path = Path();
    for (var x = -size.height; x < size.width; x += band * 2) {
      path
        ..moveTo(x, size.height)
        ..lineTo(x + band, size.height)
        ..lineTo(x + band + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}

/// A dashed black rule, like a tear-off line.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 2, width: double.infinity, child: CustomPaint(painter: _DashPainter()));
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = BP.paper;
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 7, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}
