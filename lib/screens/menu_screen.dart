import 'dart:math';
import 'package:flutter/material.dart';
import 'game_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final t = _ctrl.value * 12;
          return Stack(children: [
            // Stars
            CustomPaint(painter: _StarsPainter(t), size: Size.infinite),
            // Marching sergeants banner
            Positioned(
              top: 120,
              left: 0, right: 0,
              child: _MarchingBanner(t: t),
            ),
            // Title
            Positioned(
              top: 60,
              left: 0, right: 0,
              child: Column(children: [
                Text('MAMLA', style: TextStyle(
                  fontSize: 52, fontWeight: FontWeight.w900,
                  color: Colors.yellowAccent,
                  letterSpacing: 6,
                  shadows: [
                    Shadow(blurRadius: 20, color: Colors.orange.withValues(alpha: 0.8)),
                    Shadow(blurRadius: 40, color: Colors.red.withValues(alpha: 0.4)),
                  ],
                )),
                Text('INVADERS', style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 10,
                  shadows: [Shadow(blurRadius: 12, color: Colors.blue.withValues(alpha: 0.6))],
                )),
              ]),
            ),
            // Subtitle
            Positioned(
              top: 245,
              left: 24, right: 24,
              child: Text(
                'The corrupt traffic sergeants of BD are throwing mamlas!\nRide and dodge — your honk is your weapon!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.6),
              ),
            ),
            // TAP TO PLAY button
            Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 160),
                GestureDetector(
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const GameScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.orange.shade700, Colors.red.shade700]),
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 2)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                      Text('🏍️', style: TextStyle(fontSize: 22)),
                      SizedBox(width: 12),
                      Text('TAP TO RIDE', style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                    ]),
                  ),
                ),
              ],
            )),
            // Legend
            Positioned(
              bottom: 80, left: 0, right: 0,
              child: Column(children: const [
                Text('😤 = 10 pts   😠 = 25 pts   🤬 = 50 pts', style: TextStyle(color: Colors.white54, fontSize: 12)),
                SizedBox(height: 6),
                Text('🛡️ Shield   ⚡ Multi-shot   ⏱️ Slow-mo', style: TextStyle(color: Colors.white54, fontSize: 12)),
                SizedBox(height: 6),
                Text('Swipe UP to unleash VIRAL BLAST 🔥', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
              ]),
            ),
            // Controls hint
            Positioned(
              bottom: 30, left: 0, right: 0,
              child: const Text(
                'Hold LEFT / RIGHT sides to move • Auto-fires',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ── Marching banner of sergeants ─────────────────────────────────────────────
class _MarchingBanner extends StatelessWidget {
  final double t;
  const _MarchingBanner({required this.t});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Stack(clipBehavior: Clip.none, children: [
        for (int i = 0; i < 7; i++)
          Positioned(
            left: ((i * 48.0 - t * 28) % (7 * 48.0 + 48) - 48),
            top: 2 + sin(t * 2.5 + i) * 4,
            child: Text(
              i % 3 == 0 ? '😤' : i % 3 == 1 ? '😠' : '🤬',
              style: const TextStyle(fontSize: 30),
            ),
          ),
      ]),
    );
  }
}

// ── Starfield ────────────────────────────────────────────────────────────────
class _StarsPainter extends CustomPainter {
  final double t;
  _StarsPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(7);
    final p = Paint();
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF060612));
    for (int i = 0; i < 90; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * (0.8 + i * 0.13) + i));
      p.color = Colors.white.withValues(alpha: tw * 0.6);
      canvas.drawCircle(Offset(x, y), 0.4 + rng.nextDouble() * 1.2, p);
    }
  }
  @override bool shouldRepaint(_StarsPainter old) => true;
}
