import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import '../logic/story.dart';
import 'theme.dart';
import 'widgets.dart';

/// Story mode's shift list: ten handcrafted levels on Panel 7. Cleared
/// shifts can be replayed; the next one is open; the rest are locked.
class StoryOverlay extends StatefulWidget {
  const StoryOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<StoryOverlay> createState() => _StoryOverlayState();
}

class _StoryOverlayState extends State<StoryOverlay> {
  ButtonPanicGame get game => widget.game;
  final _scroll = ScrollController();
  final _nextKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Bring the next shift into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _nextKey.currentContext;
      if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.3);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _card(StoryLevel lv, {required int cleared, required bool wide}) {
    final done = lv.number <= cleared;
    final next = lv.number == cleared + 1;
    final locked = lv.number > cleared + 1;
    final attempts = game.store.storyAttempts(lv.number);
    final status = done ? 'CLEARED' : (next ? 'NEXT' : 'LOCKED');
    final statusColour = done ? BP.muted : (next ? BP.hazard : BP.faint);
    final number = lv.number.toString().padLeft(2, '0');
    final card = Container(
      key: next ? _nextKey : null,
      margin: const EdgeInsets.only(bottom: BP.s2),
      padding: EdgeInsets.all(wide ? BP.s4 : BP.s3),
      decoration: BoxDecoration(
        color: next ? BP.inkSoft : BP.panel,
        border: Border(
          left: BorderSide(color: next ? BP.hazard : (done ? BP.line : BP.panel), width: 3),
          top: const BorderSide(color: BP.line, width: 0.5),
          right: const BorderSide(color: BP.line, width: 0.5),
          bottom: const BorderSide(color: BP.line, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: wide ? 64 : 48,
            child: Text(number, style: BP.d(wide ? 40 : 32, color: locked ? BP.faint : BP.paper, height: 1)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lv.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BP.d(wide ? 24 : 20, color: locked ? BP.faint : BP.paper, height: 1.1, spacing: 1),
                      ),
                    ),
                    Text(status, style: BP.label(10, color: statusColour)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  locked ? 'Clear shift ${lv.number - 1} first.' : lv.briefing,
                  style: BP.t(wide ? 14 : 13, color: locked ? BP.faint : BP.muted, weight: FontWeight.w600, height: 1.3),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: BP.s3,
                  runSpacing: 4,
                  children: [
                    Text('${lv.length} ROUNDS', style: BP.label(10, color: BP.onInk)),
                    if (lv.twist != null && !locked) Text('NEW: ${lv.twist!.toUpperCase()}', style: BP.label(10, color: BP.signal)),
                    if (attempts > 0) Text('$attempts ${attempts == 1 ? 'ATTEMPT' : 'ATTEMPTS'}', style: BP.label(10, color: BP.onInk)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (locked) return Semantics(label: 'Shift $number, ${lv.title}, locked', excludeSemantics: true, child: card);
    return Semantics(
      button: true,
      label: 'Shift $number, ${lv.title}, ${done ? 'cleared, play again' : 'play'}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: Key('shift${lv.number}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => game.startStory(lv.number),
          child: card,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = game.wide;
    final cleared = game.store.storyCleared;
    return ColoredBox(
      color: const Color(0xF50B0C0E),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: EdgeInsets.fromLTRB(wide ? BP.s6 : BP.s3, wide ? BP.s5 : BP.s3, wide ? BP.s6 : BP.s3, wide ? BP.s4 : BP.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('STORY  \u00b7  THE NIGHT SHIFT', style: BP.label(11, color: BP.signal)),
                            Semantics(header: true, child: Text('PANEL 7', style: BP.d(wide ? 48 : 34, height: 1))),
                          ],
                        ),
                      ),
                      StarkAction(
                        key: const Key('closeStory'),
                        label: 'CLOSE',
                        size: 11,
                        keyHint: wide ? 'ESC' : null,
                        semantic: 'Close story',
                        onTap: game.closePanel,
                      ),
                    ],
                  ),
                  const SizedBox(height: BP.s2),
                  Text(
                    'Ten night shifts watching one button. Nobody will tell you what it does. Get through every round of a shift to unlock the next.',
                    style: BP.t(wide ? 15 : 13, color: BP.muted, weight: FontWeight.w600, height: 1.35),
                  ),
                  const SizedBox(height: BP.s2),
                  Text('$cleared/${storyLevels.length} SHIFTS CLEARED', style: BP.label(10, color: BP.onInk)),
                  const SizedBox(height: BP.s3),
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      padding: EdgeInsets.zero,
                      children: [for (final lv in storyLevels) _card(lv, cleared: cleared, wide: wide)],
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(height: BP.s2),
                    const KeyHints([('SPACE', 'PLAY NEXT SHIFT'), ('ESC', 'CLOSE')]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
