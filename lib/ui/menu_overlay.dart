import 'package:flutter/material.dart';

import '../game/button_panic_game.dart';
import '../logic/run_engine.dart';

class MenuOverlay extends StatefulWidget {
  const MenuOverlay({super.key, required this.game});
  final ButtonPanicGame game;

  @override
  State<MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<MenuOverlay> {
  ButtonPanicGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final today = game.clock();
    final daily = game.store.dailyFor(today);
    final best = game.store.bestEndless;
    return Container(
      color: const Color(0xFF111117),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'BUTTON\nPANIC',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 56, height: 0.95, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 6),
              const Text(
                'working title',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white38, letterSpacing: 1.5),
              ),
              const SizedBox(height: 18),
              const Text(
                'Do what it says. One wrong move and it\'s over.\nIt gets faster. And stranger.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 32),
              _BigButton(
                key: const Key('dailyButton'),
                label: 'DAILY RUN',
                sub: daily == null
                    ? '${prettyDate(today)} \u00b7 same rounds for everyone'
                    : 'Today: ${daily.firstScore} rounds \u00b7 best ${daily.bestScore}',
                color: const Color(0xFFE53935),
                onTap: () => game.startRun(GameMode.daily),
              ),
              const SizedBox(height: 14),
              _BigButton(
                key: const Key('endlessButton'),
                label: 'ENDLESS',
                sub: best == 0 ? 'New round types unlock as you go' : 'Best: $best rounds',
                color: const Color(0xFF1E88E5),
                onTap: () => game.startRun(GameMode.endless),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Toggle(
                    icon: game.audio.enabled ? Icons.volume_up : Icons.volume_off,
                    label: 'Sound',
                    on: game.audio.enabled,
                    onTap: () => setState(() => game.setSound(!game.audio.enabled)),
                  ),
                  const SizedBox(width: 12),
                  _Toggle(
                    icon: Icons.vibration,
                    label: 'Vibration',
                    on: game.haptics.enabled,
                    onTap: () => setState(() => game.setHaptics(!game.haptics.enabled)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({super.key, required this.label, required this.sub, required this.color, required this.onTap});
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: on ? Colors.white : Colors.white38),
      label: Text('$label ${on ? 'on' : 'off'}', style: TextStyle(color: on ? Colors.white : Colors.white38)),
      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
    );
  }
}
