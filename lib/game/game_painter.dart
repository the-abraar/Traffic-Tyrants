import 'dart:math';
import 'package:flutter/material.dart';
import 'constants.dart';
import 'entities.dart';
import 'game_engine.dart';

class GamePainter extends CustomPainter {
  final GameEngine engine;
  final double t; // time for animations

  GamePainter(this.engine, this.t);

  // Reusable paints
  final _p     = Paint();
  final _pFill = Paint()..style = PaintingStyle.fill;
  final _pStr  = Paint()..style = PaintingStyle.stroke;

  static final _rng = Random();

  // TextPainter layout is the most expensive per-frame cost (~80-100 layouts
  // per frame uncached). Cache by text/size/color; alpha is quantized to 1/20
  // steps so fading text still gets cache hits. Bounded to avoid growth.
  static final Map<String, TextPainter> _tpCache = {};

  static TextPainter _tp(String text, double fontSize, Color color, {bool emoji = false}) {
    final a = ((color.a * 20).round() / 20).clamp(0.0, 1.0);
    final c = color.withValues(alpha: a);
    final key = '$text|$fontSize|${c.toARGB32()}|$emoji';
    var tp = _tpCache[key];
    if (tp == null) {
      if (_tpCache.length > 300) _tpCache.clear();
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: emoji
              ? TextStyle(fontSize: fontSize)
              : TextStyle(
                  fontSize: fontSize,
                  color: c,
                  fontWeight: FontWeight.w700,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 340);
      _tpCache[key] = tp;
    }
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Screen shake transform
    if (engine.shake > 0) {
      final dx = (_rng.nextDouble() - 0.5) * 10 * engine.shake;
      final dy = (_rng.nextDouble() - 0.5) * 10 * engine.shake;
      canvas.save();
      canvas.translate(dx, dy);
    }

    _drawBackground(canvas, size);
    _drawStars(canvas, size);
    _drawCityline(canvas, size);
    _drawRoad(canvas, size);

    // ── Game entities ─────────────────────────────────────────────────────────
    _drawPowerUps(canvas);
    _drawBoss(canvas);
    _drawEnemies(canvas);
    _drawBullets(canvas);
    _drawMamlas(canvas);
    _drawPlayer(canvas, size);
    _drawExplosions(canvas);
    _drawFloatingTexts(canvas);

    if (engine.shake > 0) canvas.restore();

    // ── HUD (no shake) ────────────────────────────────────────────────────────
    _drawHUD(canvas, size);

    // ── Phase overlays ────────────────────────────────────────────────────────
    if (engine.phase == GamePhase.bossWarning) _drawBossWarning(canvas, size);
    if (engine.phase == GamePhase.levelComplete) _drawLevelComplete(canvas, size);
  }

  // ── Background ───────────────────────────────────────────────────────────────

  static Shader? _bgShader;
  static Size? _bgSize;
  static final _bgPaint = Paint();

  void _drawBackground(Canvas canvas, Size size) {
    if (_bgShader == null || _bgSize != size) {
      _bgShader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF060612), Color(0xFF0D0D2B), Color(0xFF111122)],
      ).createShader(Offset.zero & size);
      _bgSize = size;
      _bgPaint.shader = _bgShader;
    }
    canvas.drawRect(Offset.zero & size, _bgPaint);
  }

  void _drawStars(Canvas canvas, Size size) {
    // Seed the stars with a stable hash so they don't flicker
    final rng = Random(42);
    _p.color = Colors.white;
    for (int i = 0; i < 80; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.65;
      final r = 0.4 + rng.nextDouble() * 1.0;
      final twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * (1 + i * 0.17) + i));
      _p.color = Colors.white.withValues(alpha: twinkle * 0.75);
      canvas.drawCircle(Offset(x, y), r, _p);
    }
  }

  void _drawCityline(Canvas canvas, Size size) {
    final rng = Random(99);
    final paint = Paint()..color = const Color(0xFF0A0A1A);
    double x = 0;
    while (x < size.width) {
      final w = 14.0 + rng.nextDouble() * 32;
      final h = 30.0 + rng.nextDouble() * 60;
      canvas.drawRect(Rect.fromLTWH(x, size.height - h - 55, w, h), paint);
      x += w + rng.nextDouble() * 6;
    }
  }

  void _drawRoad(Canvas canvas, Size size) {
    final roadY = size.height - 52;
    _pFill.color = const Color(0xFF1A1A1A);
    canvas.drawRect(Rect.fromLTWH(0, roadY, size.width, 52), _pFill);
    // Dashes
    _pFill.color = const Color(0xFFFFDD00).withValues(alpha: 0.5);
    final dashW = 24.0, gap = 18.0, dashH = 3.0;
    final yc = roadY + 14;
    double dx = (t * 80) % (dashW + gap);
    while (dx - (dashW + gap) < size.width) {
      canvas.drawRect(Rect.fromLTWH(dx, yc, dashW, dashH), _pFill);
      dx += dashW + gap;
    }
  }

  // ── Enemies ───────────────────────────────────────────────────────────────────

  void _drawEnemies(Canvas canvas) {
    for (final e in engine.enemies) {
      if (!e.alive) continue;
      final (ex, ey) = engine.ePos(e);
      final bob = sin(e.animTimer) * 2.5;
      _drawSergeant(canvas, ex, ey + bob, e);
    }
  }

  void _drawSergeant(Canvas canvas, double cx, double cy, Enemy e) {
    final r = 17.0 * engine.enemyScale; // matches engine collision scale

    // Body circle
    _pFill.color = e.hatColor;
    canvas.drawCircle(Offset(cx, cy), r, _pFill);

    // Hat (trapezoid on top)
    final hatPaint = Paint()..color = e.hatColor.withValues(red: e.hatColor.r * 0.7);
    final hat = Path()
      ..moveTo(cx - r * 0.6, cy - r * 0.55)
      ..lineTo(cx + r * 0.6, cy - r * 0.55)
      ..lineTo(cx + r * 0.4, cy - r * 1.1)
      ..lineTo(cx - r * 0.4, cy - r * 1.1)
      ..close();
    canvas.drawPath(hat, hatPaint);
    // Hat brim
    _pFill.color = Colors.black.withValues(alpha: 0.6);
    canvas.drawRect(Rect.fromLTWH(cx - r * 0.7, cy - r * 0.65, r * 1.4, 3), _pFill);

    // Badge star
    _drawEmoji(canvas, '⭐', cx + r * 0.35, cy - r * 0.9, 9 * engine.enemyScale);

    // Face emoji
    _drawEmoji(canvas, e.emoji, cx, cy + 1, 22 * engine.enemyScale);

    // Angry arms (outstretched)
    final armAngle = sin(e.animTimer * 1.5) * 0.3;
    _pStr
      ..color = e.hatColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - r * 0.8, cy + 2),
      Offset(cx - r * 1.6, cy + 4 + sin(armAngle) * 5), _pStr);
    canvas.drawLine(
      Offset(cx + r * 0.8, cy + 2),
      Offset(cx + r * 1.6, cy + 4 + sin(-armAngle) * 5), _pStr);
  }

  // ── Boss ─────────────────────────────────────────────────────────────────────

  void _drawBoss(Canvas canvas) {
    final b = engine.boss;
    if (b == null || !b.active) return;

    final pulse = 0.9 + 0.1 * sin(t * 6);

    // Aura
    _pFill.color = Colors.red.withValues(alpha: 0.15 * pulse);
    canvas.drawCircle(Offset(b.x, b.y), 52, _pFill);

    // Body
    _pFill.color = const Color(0xFF1A1A8E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(b.x, b.y), width: 80, height: 60), const Radius.circular(12)),
      _pFill);

    // Hat (bigger)
    _pFill.color = const Color(0xFF0A0A5E);
    canvas.drawRect(Rect.fromLTWH(b.x - 32, b.y - 38, 64, 8), _pFill);
    canvas.drawRect(Rect.fromLTWH(b.x - 22, b.y - 60, 44, 28), _pFill);

    // Stars
    for (int i = 0; i < 3; i++) {
      _drawEmoji(canvas, '⭐', b.x - 18 + i * 18.0, b.y - 28, 12);
    }

    // Face
    _drawEmoji(canvas, '👿', b.x, b.y + 4, 36);

    // HP bar
    _pFill.color = Colors.red.shade800;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(b.x - 44, b.y - 70, 88, 8), const Radius.circular(4)), _pFill);
    _pFill.color = Colors.red;
    final hpW = 88.0 * (b.hp / b.maxHp);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(b.x - 44, b.y - 70, hpW, 8), const Radius.circular(4)), _pFill);

    // Label
    _drawText(canvas, '👮 SUPER INSPECTOR', b.x, b.y - 80, 11, Colors.yellowAccent);
  }

  // ── Bullets ───────────────────────────────────────────────────────────────────

  void _drawBullets(Canvas canvas) {
    for (final b in engine.bullets) {
      if (!b.active) continue;
      // Glow
      _pFill.color = Colors.yellow.withValues(alpha: 0.3);
      canvas.drawCircle(Offset(b.x, b.y), 7, _pFill);
      // Core
      _pFill.color = Colors.yellow;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(b.x, b.y), width: kBulletW, height: kBulletH),
          const Radius.circular(3)),
        _pFill);
      // Tip
      _pFill.color = Colors.white;
      canvas.drawCircle(Offset(b.x, b.y - kBulletH / 2 + 2), 2.5, _pFill);
    }
  }

  // ── Mamlas ────────────────────────────────────────────────────────────────────

  void _drawMamlas(Canvas canvas) {
    for (final m in engine.mamlas) {
      if (!m.active) continue;
      canvas.save();
      canvas.translate(m.x, m.y);
      canvas.rotate(m.angle);

      // Paper body
      _pFill.color = const Color(0xFFF5F0E0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: kMamlaW, height: kMamlaH),
          const Radius.circular(2)),
        _pFill);
      // Lines (text effect)
      _pFill.color = const Color(0xFF2244AA).withValues(alpha: 0.6);
      for (int i = 0; i < 4; i++) {
        canvas.drawRect(Rect.fromLTWH(-8, -9.0 + i * 5, 16, 1.5), _pFill);
      }
      // Red stamp
      _pFill.color = Colors.red.withValues(alpha: 0.7);
      canvas.drawCircle(Offset(5, 7), 4, _pFill);
      _drawText(canvas, '!', 5, 7, 7, Colors.white);

      canvas.restore();
    }
  }

  // ── Player ────────────────────────────────────────────────────────────────────

  void _drawPlayer(Canvas canvas, Size size) {
    final px = engine.playerX;
    final py = engine.playerY;
    final lean = engine.movLeft ? -0.12 : engine.movRight ? 0.12 : 0.0;

    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(lean);

    // Shield glow
    if (engine.shielded) {
      _pFill.color = Colors.cyanAccent.withValues(alpha: 0.2 + 0.15 * sin(t * 8));
      canvas.drawCircle(Offset.zero, 36, _pFill);
      _pStr..color = Colors.cyanAccent.withValues(alpha: 0.6)..strokeWidth = 2;
      canvas.drawCircle(Offset.zero, 36, _pStr);
    }

    // Invincibility blink
    if (engine.invincible && (t * 8).toInt() % 2 == 0) {
      canvas.restore();
      return;
    }

    // ── Motorcycle body ───────────────────────────────────────────────────────
    // Wheels
    _pStr..color = const Color(0xFF444444)..strokeWidth = 5;
    _pFill.color = const Color(0xFF222222);
    canvas.drawCircle(const Offset(-18, 14), 14, _pFill);
    canvas.drawCircle(const Offset(-18, 14), 14, _pStr);
    canvas.drawCircle(const Offset( 18, 14), 14, _pFill);
    canvas.drawCircle(const Offset( 18, 14), 14, _pStr);
    // Wheel spokes
    _pStr..color = const Color(0xFF666666)..strokeWidth = 1.5;
    for (int i = 0; i < 6; i++) {
      final a = i * pi / 3 + t * 4;
      canvas.drawLine(
        Offset(-18 + cos(a) * 4, 14 + sin(a) * 4),
        Offset(-18 + cos(a) * 12, 14 + sin(a) * 12), _pStr);
      canvas.drawLine(
        Offset( 18 + cos(a) * 4, 14 + sin(a) * 4),
        Offset( 18 + cos(a) * 12, 14 + sin(a) * 12), _pStr);
    }
    // Frame
    _pFill.color = const Color(0xFFCC4400);
    final body = Path()
      ..moveTo(-20, 8)
      ..lineTo(-14, -6)
      ..lineTo( 14, -6)
      ..lineTo( 20, 8)
      ..close();
    canvas.drawPath(body, _pFill);
    // Fuel tank
    _pFill.color = const Color(0xFFFF5500);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-8, -10, 16, 8), const Radius.circular(4)), _pFill);
    // Handlebars
    _pStr..color = const Color(0xFF888888)..strokeWidth = 3;
    canvas.drawLine(const Offset(12, -6), const Offset(20, -12), _pStr);
    canvas.drawLine(const Offset(20, -12), const Offset(24, -10), _pStr);
    // Exhaust
    _pStr..color = const Color(0xFF888888)..strokeWidth = 2;
    canvas.drawLine(const Offset(-20, 6), const Offset(-26, 12), _pStr);

    // ── Rider ─────────────────────────────────────────────────────────────────
    // Body
    _pFill.color = const Color(0xFF1A3A6E);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -26, 12, 16), const Radius.circular(4)), _pFill);
    // Helmet
    _pFill.color = const Color(0xFFFF4400);
    canvas.drawCircle(const Offset(0, -28), 9, _pFill);
    _pFill.color = const Color(0xFFAACCFF).withValues(alpha: 0.7);
    canvas.drawArc(const Rect.fromLTWH(-6, -34, 12, 12), 0.1, pi - 0.2, false, _pFill);
    // Arm reaching forward
    _pStr..color = const Color(0xFF1A3A6E)..strokeWidth = 4;
    canvas.drawLine(const Offset(6, -20), const Offset(18, -14), _pStr);

    canvas.restore();

    // Exhaust smoke puffs
    if (engine.movLeft || engine.movRight) {
      for (int i = 0; i < 3; i++) {
        final smokeX = px - 26 + (lean < 0 ? -4 : 0);
        final smokeY = py + 12 - i * 7;
        final alpha = (0.3 - i * 0.08).clamp(0.0, 1.0);
        _pFill.color = Colors.grey.withValues(alpha: alpha);
        canvas.drawCircle(Offset(smokeX, smokeY), 3.0 + i * 1.5, _pFill);
      }
    }

    // HONK! flash right after firing
    if (engine.shootRatio < 0.18) {
      _pFill.color = Colors.yellow.withValues(alpha: 0.5 * (1 - engine.shootRatio / 0.18));
      canvas.drawCircle(Offset(px, py - kPlayerH / 2 - 6), 14, _pFill);
    }
  }

  // ── Power-ups ─────────────────────────────────────────────────────────────────

  void _drawPowerUps(Canvas canvas) {
    for (final p in engine.powerUps) {
      if (!p.active) continue;
      final bounce = sin(t * 5 + p.x) * 3;
      // Glow ring
      _pFill.color = Colors.cyan.withValues(alpha: 0.25 + 0.1 * sin(t * 6));
      canvas.drawCircle(Offset(p.x, p.y + bounce), 18, _pFill);
      _drawEmoji(canvas, p.emoji, p.x, p.y + bounce, 24);
    }
  }

  // ── Explosions ────────────────────────────────────────────────────────────────

  void _drawExplosions(Canvas canvas) {
    for (final ex in engine.explosions) {
      final alpha = (1.0 - ex.progress).clamp(0.0, 1.0);
      for (final part in ex.particles) {
        _pFill.color = part.color.withValues(alpha: alpha);
        canvas.drawCircle(Offset(ex.ox + part.x, ex.oy + part.y), part.r * (1 - ex.progress * 0.5), _pFill);
      }
      if (ex.label.isNotEmpty && alpha > 0.3) {
        _drawText(canvas, ex.label, ex.ox, ex.oy - 20 - ex.progress * 30, 13,
            Colors.white.withValues(alpha: alpha));
      }
    }
  }

  // ── Floating texts ────────────────────────────────────────────────────────────

  void _drawFloatingTexts(Canvas canvas) {
    for (final ft in engine.floats) {
      _drawText(canvas, ft.text, ft.x, ft.y, 13, ft.color.withValues(alpha: ft.opacity.clamp(0, 1)));
    }
  }

  // ── HUD ───────────────────────────────────────────────────────────────────────

  void _drawHUD(Canvas canvas, Size size) {
    // Top bar backdrop
    _pFill.color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 52), _pFill);

    // Score
    _drawText(canvas, 'SCORE', 10, 8, 9, Colors.white54, align: TextAlign.left);
    _drawText(canvas, '${engine.score}', 10, 20, 18, Colors.white, align: TextAlign.left);

    // Level
    _drawText(canvas, 'LEVEL', size.width / 2, 8, 9, Colors.white54);
    _drawText(canvas, '${engine.level}', size.width / 2, 20, 18, Colors.yellowAccent);

    // High score
    _drawText(canvas, 'BEST', size.width - 10, 8, 9, Colors.white54, align: TextAlign.right);
    _drawText(canvas, '${engine.highScore}', size.width - 10, 20, 15, Colors.white54, align: TextAlign.right);

    // Lives (hearts) — dim lost lives instead of shrinking them
    for (int i = 0; i < 3; i++) {
      _drawEmoji(canvas, '❤️', 16 + i * 22.0, 44, 16,
          opacity: i < engine.lives ? 1.0 : 0.2);
    }

    // Combo
    if (engine.combo >= 2) {
      final comboColor = engine.combo >= 6 ? Colors.red : engine.combo >= 4 ? Colors.orange : Colors.yellowAccent;
      _drawText(canvas, '🔥 COMBO ×${engine.combo}', size.width / 2, 44, 14, comboColor);
    }

    // Status badges (right side HUD)
    double badgeX = size.width - 8;
    if (engine.shielded) {
      _drawEmoji(canvas, '🛡️', badgeX, 44, 16); badgeX -= 24;
    }
    if (engine.multiShot) {
      _drawEmoji(canvas, '⚡', badgeX, 44, 16); badgeX -= 24;
    }
    if (engine.slowMo) {
      _drawEmoji(canvas, '⏱️', badgeX, 44, 16);
    }

    // Viral charge bar
    const barH = 6.0;
    final barW = size.width * 0.5;
    final barX = (size.width - barW) / 2;
    const barY = 57.0;

    _pFill.color = Colors.white12;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(barX, barY, barW, barH), const Radius.circular(3)), _pFill);
    if (engine.viralCharge > 0) {
      final charged = engine.viralCharge >= 1.0;
      _pFill.color = charged ? Colors.orange : Colors.orange.withValues(alpha: 0.55);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(barX, barY, barW * engine.viralCharge, barH), const Radius.circular(3)), _pFill);
      if (charged) {
        _drawText(canvas, '🔥 VIRAL READY – swipe up!', size.width / 2, barY + barH + 9, 10,
            Colors.orange.withValues(alpha: 0.8 + 0.2 * sin(t * 6)));
      }
    }
  }

  // ── Phase overlays ────────────────────────────────────────────────────────────

  void _drawBossWarning(Canvas canvas, Size size) {
    _pFill.color = Colors.black.withValues(alpha: 0.5);
    canvas.drawRect(Offset.zero & size, _pFill);
    _drawText(canvas, '⚠️ BOSS APPROACHING ⚠️', size.width / 2, size.height * 0.40, 22, Colors.red);
    _drawText(canvas, 'SUPER INSPECTOR', size.width / 2, size.height * 0.50, 18, Colors.white);
    _drawText(canvas, 'get ready…', size.width / 2, size.height * 0.58, 14, Colors.white54);
  }

  void _drawLevelComplete(Canvas canvas, Size size) {
    _pFill.color = Colors.black.withValues(alpha: 0.3);
    canvas.drawRect(Offset.zero & size, _pFill);
    _drawText(canvas, '✅ LEVEL ${engine.level} CLEARED!', size.width / 2, size.height * 0.42, 22, Colors.greenAccent);
    _drawText(canvas, 'next level loading…', size.width / 2, size.height * 0.52, 14, Colors.white54);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  void _drawEmoji(Canvas canvas, String emoji, double cx, double cy, double size,
      {double opacity = 1.0}) {
    if (size <= 0 || opacity <= 0) return;
    final tp = _tp(emoji, size, Colors.white, emoji: true);
    final offset = Offset(cx - tp.width / 2, cy - tp.height / 2);
    if (opacity < 1.0) {
      final bounds = offset & Size(tp.width, tp.height);
      canvas.saveLayer(bounds, Paint()..color = Colors.white.withValues(alpha: opacity));
      tp.paint(canvas, offset);
      canvas.restore();
    } else {
      tp.paint(canvas, offset);
    }
  }

  void _drawText(Canvas canvas, String text, double cx, double cy, double fontSize, Color color,
      {TextAlign align = TextAlign.center}) {
    final tp = _tp(text, fontSize, color);
    final ox = align == TextAlign.left ? cx : align == TextAlign.right ? cx - tp.width : cx - tp.width / 2;
    tp.paint(canvas, Offset(ox, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(GamePainter old) => true;
}
