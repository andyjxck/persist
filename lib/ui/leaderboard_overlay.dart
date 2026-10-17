import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../game/button_panic_game.dart';
import '../services/leaderboard.dart';
import 'theme.dart';
import 'widgets.dart';

/// A one-line text box in the game's style, for the leaderboard name.
/// Plain [EditableText], so it works without a Material ancestor.
class NameField extends StatefulWidget {
  const NameField({super.key, required this.initial, required this.onSubmit, this.autofocus = false, this.buttonLabel = 'SAVE'});
  final String initial;
  final bool autofocus;
  final String buttonLabel;

  /// Returns what's wrong with the name, or null when it was accepted.
  final Future<String?> Function(String name) onSubmit;

  @override
  State<NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<NameField> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode(debugLabel: 'leaderboard name');
  String? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final problem = await widget.onSubmit(_text.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
    if (problem == null) _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final style = BP.d(22, height: 1.15, spacing: 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _focus.requestFocus(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: BP.ink,
                    border: Border.all(color: _focus.hasFocus ? BP.hazard : BP.line, width: _focus.hasFocus ? 2 : 1),
                    borderRadius: BorderRadius.circular(BP.radius),
                  ),
                  child: Semantics(
                    textField: true,
                    label: 'Your name for the leaderboards',
                    child: EditableText(
                      key: const Key('nameField'),
                      controller: _text,
                      focusNode: _focus,
                      autofocus: widget.autofocus,
                      style: style,
                      cursorColor: BP.hazard,
                      backgroundCursorColor: BP.faint,
                      selectionColor: BP.hazard.withValues(alpha: 0.35),
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLines: 1,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(14),
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 _.\-]')),
                      ],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
              ),
            ),
            StarkAction(
              key: const Key('nameSubmit'),
              look: ActionLook.hazard,
              label: _busy ? '...' : widget.buttonLabel,
              size: 12,
              semantic: widget.buttonLabel == 'SEND' ? 'Send score' : 'Save name',
              onTap: _busy ? null : _submit,
            ),
          ],
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_problem!, key: const Key('nameProblem'), style: BP.label(11, color: BP.signal)),
          ),
      ],
    );
  }
}

/// The result screen's line about the boards: asks for a name the first
/// time, then says where the score landed.
class BoardStatus extends StatelessWidget {
  const BoardStatus({super.key, required this.game, this.live = true});
  final ButtonPanicGame game;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final lb = game.leaderboards;
    return ListenableBuilder(
      listenable: lb,
      builder: (context, _) {
        final daily = lb.pendingBoard?.startsWith('daily') ?? false;
        final which = daily ? 'TODAY\u2019S BOARD' : 'THE ENDLESS BOARD';
        final Widget body = switch (lb.status) {
          SubmitStatus.needsName => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PUT THIS ON $which', style: BP.label(11, color: BP.hazard)),
              const SizedBox(height: 6),
              NameField(initial: lb.name, buttonLabel: 'SEND', onSubmit: lb.setName),
              if (lb.error != null && lb.hasName)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(lb.error!, style: BP.label(11, color: BP.signal)),
                ),
            ],
          ),
          SubmitStatus.sending => Text('SENDING TO $which...', style: BP.label(12, color: BP.muted)),
          SubmitStatus.sent => Row(
            children: [
              Expanded(
                child: Text(
                  lb.lastRank != null && lb.lastRank! > 0 ? '#${lb.lastRank} ON $which' : 'SENT TO $which',
                  key: const Key('boardRank'),
                  style: BP.d(22, color: BP.hazard, spacing: 1),
                ),
              ),
              StarkAction(
                key: const Key('viewBoard'),
                look: ActionLook.chip,
                label: 'VIEW',
                size: 11,
                color: BP.cream,
                semantic: 'View leaderboard',
                onTap: live ? () => game.openPanel('leaderboard') : null,
              ),
            ],
          ),
          SubmitStatus.failed => Text(
            'NOT ON THE BOARD: ${(lb.error ?? '').toUpperCase()}',
            style: BP.label(11, color: BP.muted),
          ),
          SubmitStatus.none => const SizedBox.shrink(),
        };
        if (lb.status == SubmitStatus.none) return body;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BP.panel,
            border: Border.all(color: BP.line),
            borderRadius: BorderRadius.circular(BP.radius),
          ),
          child: body,
        );
      },
    );
  }
}

/// The leaderboards: today's Daily and all-time Endless for this version of
/// the game (phone or desktop).
class LeaderboardOverlay extends StatefulWidget {
  const LeaderboardOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<LeaderboardOverlay> createState() => _LeaderboardOverlayState();
}

class _LeaderboardOverlayState extends State<LeaderboardOverlay> {
  ButtonPanicGame get game => widget.game;
  bool _renaming = false;

  String get _board =>
      game.boardTab.value == 0 ? Boards.daily(game.dailyVariant, game.clock()) : Boards.endless(game.dailyVariant);

  @override
  void initState() {
    super.initState();
    game.boardTab.addListener(_load);
    // Open on the board the last run was on.
    final pending = game.leaderboards.pendingBoard;
    if (pending != null) game.boardTab.value = pending.startsWith('endless') ? 1 : 0;
    _load();
  }

  @override
  void dispose() {
    game.boardTab.removeListener(_load);
    super.dispose();
  }

  void _load() {
    game.leaderboards.load(_board);
    if (mounted) setState(() {});
  }

  Widget _tab(String label, int index) {
    final on = game.boardTab.value == index;
    return Expanded(
      child: Semantics(
        selected: on,
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => game.boardTab.value = index,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: on ? BP.signal : BP.line, width: on ? 3 : 1)),
              ),
              alignment: Alignment.center,
              child: Text(label, style: BP.label(12, color: on ? BP.paper : BP.onInk)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(LeaderboardEntry e) {
    final me = e.me;
    return Container(
      key: me ? const Key('myRow') : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: me ? BP.hazard.withValues(alpha: 0.14) : null,
        border: Border(
          left: BorderSide(color: me ? BP.hazard : const Color(0x00000000), width: 3),
          bottom: const BorderSide(color: BP.line, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('${e.rank}', style: BP.d(20, color: e.rank <= 3 ? BP.signal : BP.faint, height: 1.1)),
          ),
          Expanded(
            child: Text(
              e.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BP.label(14, color: me ? BP.hazard : BP.paper),
            ),
          ),
          Text('${e.score}', style: BP.d(22, color: me ? BP.hazard : BP.cream, height: 1.1)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lb = game.leaderboards;
    final wide = game.wide;
    return ListenableBuilder(
      listenable: lb,
      builder: (context, _) {
        final board = _board;
        final rows = lb.entries(board);
        final loading = lb.isLoading(board);
        final error = lb.loadError(board);
        final Widget list;
        if (rows == null && loading) {
          list = Center(child: Text('LOADING...', style: BP.label(12, color: BP.muted)));
        } else if (rows == null && error != null) {
          list = Center(child: Text(error.toUpperCase(), textAlign: TextAlign.center, style: BP.label(12, color: BP.muted)));
        } else if (rows == null || rows.isEmpty) {
          list = Center(
            child: Text(
              game.boardTab.value == 0 ? 'NOBODY HAS PLAYED TODAY YET.' : 'NO SCORES YET.',
              style: BP.label(12, color: BP.muted),
            ),
          );
        } else {
          list = ListView(padding: EdgeInsets.zero, children: [for (final e in rows) _row(e)]);
        }
        return ColoredBox(
          color: const Color(0xF20B0C0E),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.all(wide ? BP.s6 : BP.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Semantics(header: true, child: Text('BOARDS', style: BP.d(wide ? 44 : 34)))),
                          StarkAction(
                            key: const Key('closeBoards'),
                            label: 'CLOSE',
                            size: 11,
                            keyHint: wide ? 'ESC' : null,
                            semantic: 'Close leaderboards',
                            onTap: game.closePanel,
                          ),
                        ],
                      ),
                      Text(
                        '${Boards.version(game.dailyVariant).toUpperCase()} VERSION  \u00b7  BEST SCORE PER PLAYER',
                        style: BP.label(10, color: BP.onInk),
                      ),
                      const SizedBox(height: BP.s3),
                      Row(children: [_tab('TODAY  \u00b7  DAILY', 0), _tab('ALL-TIME  \u00b7  ENDLESS', 1)]),
                      Expanded(child: list),
                      const SizedBox(height: BP.s3),
                      if (_renaming || !lb.hasName)
                        NameField(
                          initial: lb.name,
                          autofocus: _renaming,
                          onSubmit: (n) async {
                            final problem = await lb.setName(n);
                            if (problem == null && mounted) {
                              setState(() => _renaming = false);
                              lb.load(_board, force: true);
                            }
                            return problem;
                          },
                        )
                      else
                        Row(
                          children: [
                            Text('YOUR NAME', style: BP.label(10, color: BP.onInk)),
                            const SizedBox(width: BP.s2),
                            Expanded(
                              child: Text(lb.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: BP.label(14, color: BP.paper)),
                            ),
                            StarkAction(
                              key: const Key('renameButton'),
                              look: ActionLook.chip,
                              label: 'CHANGE',
                              size: 10,
                              color: BP.cream,
                              semantic: 'Change your name',
                              onTap: () => setState(() => _renaming = true),
                            ),
                          ],
                        ),
                      if (wide) ...[
                        const SizedBox(height: BP.s2),
                        const KeyHints([('\u2190 \u2192', 'SWITCH BOARD'), ('ESC', 'CLOSE')]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
