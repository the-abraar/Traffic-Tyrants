import 'package:flutter/material.dart';
import '../game/game_engine.dart';
import 'menu_screen.dart';
import 'game_screen.dart';

class GameOverScreen extends StatefulWidget {
  final GameEngine engine;
  const GameOverScreen({super.key, required this.engine});
  @override
  State<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends State<GameOverScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final isHigh = e.score >= e.highScore && e.score > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fade,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0015), Color(0xFF150008), Color(0xFF050010)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                const Text('💀', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 12),

                // Title
                Text(
                  isHigh ? '🏆 NEW RECORD!' : 'CASE FILED!',
                  style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w900,
                    color: isHigh ? Colors.yellowAccent : Colors.redAccent,
                    letterSpacing: 3,
                    shadows: [Shadow(blurRadius: 20,
                        color: isHigh ? Colors.orange : Colors.red)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The sergeants won this round.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
                const SizedBox(height: 36),

                // Score card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(children: [
                    _Row('SCORE',      '${e.score}',     Colors.yellowAccent),
                    const Divider(color: Colors.white12, height: 20),
                    _Row('BEST',       '${e.highScore}', Colors.white70),
                    const Divider(color: Colors.white12, height: 20),
                    _Row('LEVEL',      '${e.level}',     Colors.cyanAccent),
                    const Divider(color: Colors.white12, height: 20),
                    _Row('ENEMIES JAILED',
                        '${e.kills}',   Colors.greenAccent),
                  ]),
                ),
                const SizedBox(height: 44),

                // Buttons
                _BigBtn(
                  label: '🏍️  RIDE AGAIN',
                  color1: Colors.orange.shade700,
                  color2: Colors.red.shade700,
                  // The engine passed here is already disposed (GameScreen owns
                  // its lifecycle); a new GameScreen creates a fresh engine.
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const GameScreen())),
                ),
                const SizedBox(height: 14),
                _BigBtn(
                  label: '🏠  MAIN MENU',
                  color1: Colors.blueGrey.shade700,
                  color2: Colors.blueGrey.shade900,
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MenuScreen())),
                ),
                const SizedBox(height: 30),
                Text(
                  '"Every mamla has an end.\nRide through it."',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Row(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1.5)),
      Text(value,  style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
    ],
  );
}

class _BigBtn extends StatelessWidget {
  final String label;
  final Color color1, color2;
  final VoidCallback onTap;
  const _BigBtn({required this.label, required this.color1, required this.color2, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color1, color2]),
          borderRadius: BorderRadius.circular(36),
          boxShadow: [BoxShadow(color: color1.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 1)],
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
              color: Colors.white, letterSpacing: 1.5)),
      ),
    ),
  );
}
