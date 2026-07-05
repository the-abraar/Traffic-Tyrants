import 'dart:math';
import 'package:flutter/material.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────
enum EnemyType { constable, sergeant, inspector }
enum PowerUpType { shield, multiShot, slowMo }
enum GamePhase { getReady, playing, bossWarning, bossFight, levelComplete, gameOver }

// ── Enemy ─────────────────────────────────────────────────────────────────────
class Enemy {
  final int row, col;
  final EnemyType type;
  bool alive = true;
  int hp;
  double hitFlash = 0; // brief white flash when damaged but not killed
  double animTimer;
  static final _rng = Random();

  Enemy({required this.row, required this.col, required this.type})
      : hp = type == EnemyType.inspector ? 2 : 1,
        animTimer = _rng.nextDouble() * 6.28;

  int get points => switch (type) {
        EnemyType.constable  => 10,
        EnemyType.sergeant   => 25,
        EnemyType.inspector  => 50,
      };

  String get emoji => switch (type) {
        EnemyType.constable  => '😤',
        EnemyType.sergeant   => '😠',
        EnemyType.inspector  => '🤬',
      };

  Color get hatColor => switch (type) {
        EnemyType.constable  => const Color(0xFF8B7355),
        EnemyType.sergeant   => const Color(0xFF3D5A23),
        EnemyType.inspector  => const Color(0xFF1A1A8E),
      };
}

// ── Boss ──────────────────────────────────────────────────────────────────────
class Boss {
  double x, y;
  double vx = 100;
  double phase = 0;
  int hp, maxHp;
  double shootTimer = 1.5;
  bool active = true;

  Boss({required double sw, int level = 3})
      : x = sw / 2,
        y = 110,
        hp = hpFor(level),
        maxHp = hpFor(level);

  // 6 HP for the first boss (level 3), +2 per subsequent boss, capped at 30.
  static int hpFor(int level) => (6 + ((level ~/ 3) - 1).clamp(0, 12) * 2).clamp(6, 30);
}

// ── Bullet ────────────────────────────────────────────────────────────────────
class Bullet {
  double x, y;
  double vx, vy;
  bool active = true;

  Bullet({required this.x, required this.y, this.vx = 0, double speed = 500})
      : vy = -speed;
}

// ── Mamla ─────────────────────────────────────────────────────────────────────
class Mamla {
  double x, y, speed, angle = 0, spin;
  double vx; // horizontal drift — sergeants aim at the player
  bool active = true;

  Mamla({required this.x, required this.y, required this.speed, this.vx = 0})
      : spin = (Random().nextDouble() - 0.5) * 5;
}

// ── PowerUp ───────────────────────────────────────────────────────────────────
class PowerUp {
  double x, y;
  final PowerUpType type;
  bool active = true;

  PowerUp({required this.x, required this.y, required this.type});

  String get emoji => switch (type) {
        PowerUpType.shield    => '🛡️',
        PowerUpType.multiShot => '⚡',
        PowerUpType.slowMo    => '⏱️',
      };
}

// ── Explosion ─────────────────────────────────────────────────────────────────
class Explosion {
  final double ox, oy;
  double progress = 0; // 0 → 1
  final String label;
  final List<Particle> parts;
  static final _rng = Random();

  Explosion({required this.ox, required this.oy, this.label = ''})
      : parts = List.generate(14, (_) {
          final a = _rng.nextDouble() * pi * 2;
          final s = 45 + _rng.nextDouble() * 120;
          return Particle(
            vx: cos(a) * s,
            vy: sin(a) * s,
            color: [
              Colors.orange,
              Colors.yellow,
              Colors.red,
              Colors.white,
              const Color(0xFFFF6B35),
            ][_rng.nextInt(5)],
            r: 2.5 + _rng.nextDouble() * 4,
          );
        });

  List<Particle> get particles => parts;
}

class Particle {
  double x = 0, y = 0;
  double vx, vy;
  final Color color;
  final double r;
  Particle({required this.vx, required this.vy, required this.color, required this.r});
}

// ── FloatingText ──────────────────────────────────────────────────────────────
class FloatingText {
  double x, y;
  final double vy = -55;
  double opacity = 1.0;
  final String text;
  final Color color;
  FloatingText({required this.x, required this.y, required this.text, required this.color});
}
