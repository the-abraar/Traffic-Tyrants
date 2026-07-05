import 'dart:math';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio.dart';
import 'constants.dart';
import 'entities.dart';

class GameEngine extends ChangeNotifier {
  // ── Screen ───────────────────────────────────────────────────────────────────
  double sw = 0, sh = 0;
  double topPad = 0; // display-cutout inset; HUD and formation shift down by it

  // ── Formation ────────────────────────────────────────────────────────────────
  double fmX = 0, fmY = 0, fmDir = 1, fmSpeed = kEnemyBaseSpeed;
  // Responsive layout: spacing shrinks on narrow screens so the formation
  // always has room to sway (see start()).
  double spacingX = kEnemySpacingX;
  double enemyScale = 1.0;
  double get eW => kEnemyW * enemyScale;
  double get eH => kEnemyH * enemyScale;

  // ── Entities ─────────────────────────────────────────────────────────────────
  List<Enemy>      enemies      = [];
  Boss?            boss;
  final List<Bullet>      bullets      = [];
  final List<Mamla>       mamlas       = [];
  final List<PowerUp>     powerUps     = [];
  final List<Explosion>   explosions   = [];
  final List<FloatingText> floats      = [];

  // ── Player ───────────────────────────────────────────────────────────────────
  double playerX = 0;
  int    lives   = 3;
  bool shielded = false, multiShot = false, slowMo = false, invincible = false;
  double shieldT = 0, multiShotT = 0, slowMoT = 0, invincT = 0;

  // ── Input ─────────────────────────────────────────────────────────────────────
  bool movLeft = false, movRight = false;

  // ── Progression ──────────────────────────────────────────────────────────────
  int score = 0, highScore = 0, level = 1, combo = 0, kills = 0;
  double comboT = 0, viralCharge = 0;

  // ── Internal timing ──────────────────────────────────────────────────────────
  double _shootCD = 0, _enemyShootT = 1.2, _shakeT = 0, _bossWarnT = 0, _lvlDoneT = 0;
  double _readyT = 0;

  // ── Phase ─────────────────────────────────────────────────────────────────────
  GamePhase phase = GamePhase.getReady;
  bool paused = false;

  // Widgets only care about phase changes and viral readiness, so we notify on
  // those transitions instead of every tick (painting is driven separately).
  GamePhase _prevPhase = GamePhase.getReady;
  bool _prevReady = false;
  bool _disposed = false;

  // ── Ticker ───────────────────────────────────────────────────────────────────
  Ticker?  _ticker;
  Duration? _last;
  final _rng = Random();

  GameEngine() { _loadHigh(); }

  // ── Public ───────────────────────────────────────────────────────────────────

  void start(TickerProvider vsync, double w, double h, {double topPad = 0}) {
    this.topPad = topPad;
    resize(w, h);
    playerX = sw / 2;
    _reset();
    _ticker?.dispose();
    _last = null;
    _ticker = vsync.createTicker(_tick)..start();
  }

  /// Handles window resizes (desktop/web). Refits the formation layout and
  /// keeps the player on screen.
  void resize(double w, double h) {
    if (w == sw && h == sh) return;
    sw = w; sh = h;
    // Fit the formation to the screen: cap its span at kFmMaxSpanFrac of the
    // width so it always has sway room before hitting the bounce margins.
    final maxSpan = sw * kFmMaxSpanFrac;
    spacingX = min(kEnemySpacingX, (maxSpan - kEnemyW) / (kCols - 1));
    enemyScale = (spacingX / kEnemySpacingX).clamp(0.65, 1.0);
    playerX = playerX.clamp(kPlayerW / 2, sw - kPlayerW / 2);
  }

  @override
  void dispose() { _disposed = true; _ticker?.dispose(); super.dispose(); }

  void onLeft(bool v)  => movLeft  = v;
  void onRight(bool v) => movRight = v;

  void viralBlast() {
    if (viralCharge < 1.0 || paused) return;
    if (phase != GamePhase.playing && phase != GamePhase.bossFight) return;

    // Against the boss: a charged blast is a big chunk of damage.
    if (phase == GamePhase.bossFight) {
      final b = boss;
      if (b == null || !b.active) return;
      viralCharge = 0;
      b.hp -= kViralBossDamage;
      score += 100 * kViralBossDamage;
      if (score > highScore) highScore = score;
      _shakeT = 0.8;
      explosions.add(Explosion(ox: b.x, oy: b.y));
      _addFloat(b.x, b.y - 34, '🔥 VIRAL HIT! −$kViralBossDamage HP', Colors.orange);
      Sfx.bigBoom(); Sfx.tapHeavy();
      if (b.hp <= 0) _killBoss(b);
      return;
    }

    // Against the formation: wipe the two bottom-most rows that still have
    // survivors, so a charged blast is never wasted on empty rows.
    final aliveRows = enemies.where((e) => e.alive).map((e) => e.row).toSet().toList()..sort();
    if (aliveRows.isEmpty) return;
    final targets = aliveRows.length <= 2
        ? aliveRows.toSet()
        : {aliveRows[aliveRows.length - 2], aliveRows.last};
    viralCharge = 0;
    int cnt = 0;
    for (final e in enemies) {
      if (e.alive && targets.contains(e.row)) { _killEnemy(e, viral: true); cnt++; }
    }
    _shakeT = 0.7;
    _addFloat(sw / 2, sh * .45, '🔥 VIRAL BLAST! ×$cnt', Colors.orange);
    Sfx.bigBoom(); Sfx.tapHeavy();
  }

  void togglePause() {
    if (phase == GamePhase.gameOver) return;
    paused = !paused;
    notifyListeners();
  }

  double get playerY       => sh - 82;
  double get readyT        => _readyT;
  double get shake         => _shakeT.clamp(0, 1);
  int    get aliveCount    => enemies.where((e) => e.alive).length;
  // 0.0 = just fired, 1.0 = fully recharged
  double get shootRatio    => (1.0 - _shootCD / kShootCooldown).clamp(0.0, 1.0);

  // ── Enemy screen position ─────────────────────────────────────────────────────
  (double, double) ePos(Enemy e) {
    final totalW = (kCols - 1) * spacingX;
    final sx = (sw - totalW) / 2;
    return (sx + e.col * spacingX + fmX, kEnemyStartY + topPad + e.row * kEnemySpacingY + fmY);
  }

  // ── Init / Reset ──────────────────────────────────────────────────────────────

  void _reset() {
    enemies = _buildGrid();
    boss = null;
    bullets.clear(); mamlas.clear(); powerUps.clear();
    explosions.clear(); floats.clear();
    fmX = 0; fmY = 0; fmDir = 1;
    _shootCD = 0; _enemyShootT = 1.2; _shakeT = 0;
    phase = GamePhase.getReady;
    _readyT = kGetReadyDuration;
    fmSpeed = _calcFmSpeed();
  }

  void _nextLevel() {
    enemies = []; boss = null;
    bullets.clear(); mamlas.clear(); powerUps.clear(); floats.clear();
    fmX = 0; fmY = 0; fmDir = 1;
    _shootCD = 0; _enemyShootT = 1.0;
    if (level % 3 == 0) {
      phase = GamePhase.bossWarning;
      _bossWarnT = 2.8;
    } else {
      enemies = _buildGrid();
      phase = GamePhase.getReady;
      _readyT = kGetReadyDuration;
    }
    fmSpeed = _calcFmSpeed();
  }

  List<Enemy> _buildGrid() {
    final list = <Enemy>[];
    for (int r = 0; r < kRows; r++) {
      final t = r == 0 ? EnemyType.inspector
               : r <= 1 ? EnemyType.sergeant
               : EnemyType.constable;
      for (int c = 0; c < kCols; c++) {
        list.add(Enemy(row: r, col: c, type: t));
      }
    }
    return list;
  }

  // ── Tick ─────────────────────────────────────────────────────────────────────

  void _tick(Duration now) {
    double dt = _last == null ? 0 : (now - _last!).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.1) return;
    if (!paused) _update(dt);

    // Notify only on transitions widgets actually watch; the canvas repaints
    // on its own AnimationController every frame regardless.
    final ready = viralCharge >= 1.0;
    if (phase != _prevPhase || ready != _prevReady) {
      _prevPhase = phase;
      _prevReady = ready;
      notifyListeners();
    }
  }

  void _update(double dt) {
    if (phase == GamePhase.gameOver) return;

    if (phase == GamePhase.getReady) {
      _readyT -= dt;
      _movePlayer(dt, canShoot: false); // let players position themselves
      _updateFx(dt);
      if (_readyT <= 0) { phase = GamePhase.playing; _shootCD = 0.15; }
      return;
    }

    if (phase == GamePhase.bossWarning) {
      _bossWarnT -= dt;
      if (_bossWarnT <= 0) { boss = Boss(sw: sw, level: level); phase = GamePhase.bossFight; }
      return;
    }

    if (phase == GamePhase.levelComplete) {
      _lvlDoneT -= dt;
      if (_lvlDoneT <= 0) { level++; _nextLevel(); }
      return;
    }

    final spd = slowMo ? 0.32 : 1.0;

    _movePlayer(dt);
    _updateBullets(dt);
    _updateFormation(dt * spd);
    _enemyFire(dt * spd);
    _updateMamlas(dt * spd);
    _updateBoss(dt * spd);
    _updatePowerUps(dt);
    _updateFx(dt);
    _updateTimers(dt);
    _collide();
    _checkWin();
  }

  // ── Player & shooting ─────────────────────────────────────────────────────────

  void _movePlayer(double dt, {bool canShoot = true}) {
    if (movLeft)  playerX -= kPlayerSpeed * dt;
    if (movRight) playerX += kPlayerSpeed * dt;
    playerX = playerX.clamp(kPlayerW / 2, sw - kPlayerW / 2);

    if (!canShoot) return;
    _shootCD -= dt;
    if (_shootCD <= 0) {
      _fire();
      _shootCD += kShootCooldown; // += keeps the cadence steady across frames
    }
  }

  void _fire() {
    final py = playerY - kPlayerH / 2 + 4;
    if (multiShot) {
      bullets.add(Bullet(x: playerX, y: py, vx: -120));
      bullets.add(Bullet(x: playerX, y: py));
      bullets.add(Bullet(x: playerX, y: py, vx:  120));
    } else {
      bullets.add(Bullet(x: playerX, y: py));
    }
    Sfx.shot();
  }

  // ── Bullets ───────────────────────────────────────────────────────────────────

  void _updateBullets(double dt) {
    for (final b in bullets) {
      if (!b.active) continue;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      if (b.y < -30 || b.x < -30 || b.x > sw + 30) b.active = false;
    }
    bullets.removeWhere((b) => !b.active);
  }

  // ── Formation ────────────────────────────────────────────────────────────────

  void _updateFormation(double dt) {
    if (enemies.every((e) => !e.alive)) return;
    for (final e in enemies) {
      e.animTimer += dt * 2.2;
      if (e.hitFlash > 0) e.hitFlash -= dt;
    }

    fmX += fmDir * fmSpeed * dt;

    double minX = double.infinity, maxX = double.negativeInfinity;
    for (final e in enemies) {
      if (!e.alive) continue;
      final (ex, _) = ePos(e);
      if (ex < minX) minX = ex;
      if (ex > maxX) maxX = ex;
    }
    if (fmDir > 0 && maxX + eW / 2 >= sw - kFmMargin) {
      fmDir = -1; fmY += kFormationDrop;
    } else if (fmDir < 0 && minX - eW / 2 <= kFmMargin) {
      fmDir = 1; fmY += kFormationDrop;
    }
  }

  // ── Enemy shooting ────────────────────────────────────────────────────────────

  void _enemyFire(double dt) {
    _enemyShootT -= dt;
    if (_enemyShootT > 0) return;

    // Bottom-most alive in each column
    final front = <int, Enemy>{};
    for (final e in enemies) {
      if (!e.alive) continue;
      if (!front.containsKey(e.col) || e.row > front[e.col]!.row) front[e.col] = e;
    }
    if (front.isNotEmpty) {
      final shooter = front.values.elementAt(_rng.nextInt(front.length));
      final (sx, sy) = ePos(shooter);
      final spawnY = sy + eH / 2;
      final speed = kMamlaBaseSpeed + level * 12;
      // Sergeants lead their throw toward the player (capped so it's dodgeable);
      // everyone else drops straight down.
      double vx = 0;
      if (shooter.type == EnemyType.sergeant) {
        final tArrive = max(0.35, (playerY - spawnY) / speed);
        vx = ((playerX - sx) / tArrive).clamp(-kMamlaMaxAimVx, kMamlaMaxAimVx);
      }
      mamlas.add(Mamla(x: sx, y: spawnY, speed: speed, vx: vx));
    }

    final alive = enemies.where((e) => e.alive).length;
    final ratio = (alive / kTotalEnemies).clamp(0.25, 1.0);
    _enemyShootT = (1.3 - level * 0.04).clamp(0.28, 1.3) * ratio;
  }

  // ── Mamlas ────────────────────────────────────────────────────────────────────

  void _updateMamlas(double dt) {
    for (final m in mamlas) {
      if (!m.active) continue;
      m.x += m.vx * dt;
      m.y += m.speed * dt;
      m.angle += m.spin * dt;
      if (m.y > sh + 30 || m.x < -30 || m.x > sw + 30) m.active = false;
    }
    mamlas.removeWhere((m) => !m.active);
  }

  // ── Boss ──────────────────────────────────────────────────────────────────────

  void _updateBoss(double dt) {
    final b = boss; if (b == null || !b.active) return;
    b.phase += dt;
    b.x += b.vx * dt;
    b.y = 110 + topPad + sin(b.phase * 1.4) * 28;
    if (b.x < 55) { b.x = 55; b.vx = b.vx.abs() + 5; }
    if (b.x > sw - 55) { b.x = sw - 55; b.vx = -(b.vx.abs() + 5); }

    b.shootTimer -= dt;
    if (b.shootTimer <= 0) {
      for (int i = -1; i <= 1; i++) {
        final m = Mamla(x: b.x + i * 22, y: b.y + 44, speed: 155 + level * 8);
        m.spin = i * 2.5;
        mamlas.add(m);
      }
      b.shootTimer = (1.9 - level * 0.05).clamp(0.55, 1.9);
    }
  }

  // ── Power-ups ─────────────────────────────────────────────────────────────────

  void _updatePowerUps(double dt) {
    for (final p in powerUps) {
      if (!p.active) continue;
      p.y += kPowerUpFallSpeed * dt;
      if (p.y > sh + 30) p.active = false;
    }
    powerUps.removeWhere((p) => !p.active);
  }

  // ── FX ────────────────────────────────────────────────────────────────────────

  void _updateFx(double dt) {
    for (final ex in explosions) {
      ex.progress += dt * 1.6;
      for (final p in ex.particles) {
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vy += 220 * dt; // gravity
      }
    }
    explosions.removeWhere((ex) => ex.progress >= 1.0);

    for (final ft in floats) {
      ft.y += ft.vy * dt;
      ft.opacity -= dt * 1.4;
    }
    floats.removeWhere((ft) => ft.opacity <= 0);
  }

  // ── Timers ───────────────────────────────────────────────────────────────────

  void _updateTimers(double dt) {
    if (invincible) { invincT -= dt; if (invincT <= 0) invincible = false; }
    if (shielded)   { shieldT -= dt; if (shieldT <= 0) shielded   = false; }
    if (multiShot)  { multiShotT -= dt; if (multiShotT <= 0) multiShot = false; }
    if (slowMo)     { slowMoT -= dt; if (slowMoT <= 0) slowMo = false; }
    if (comboT > 0) { comboT -= dt; if (comboT <= 0) combo = 0; }
    if (_shakeT > 0) _shakeT -= dt * 2;
  }

  // ── Collisions ───────────────────────────────────────────────────────────────

  void _collide() {
    // Bullets → enemies
    for (final b in bullets) {
      if (!b.active) continue;
      for (final e in enemies) {
        if (!e.alive) continue;
        final (ex, ey) = ePos(e);
        if (_hit(b.x, b.y, kBulletW, kBulletH, ex, ey, eW, eH)) {
          b.active = false;
          e.hp--;
          if (e.hp <= 0) {
            _killEnemy(e);
          } else {
            // Inspectors take two hits: flash white and give a chip-damage bonus.
            e.hitFlash = 0.3;
            score += 5;
            if (score > highScore) highScore = score;
            _addFloat(ex, ey - 18, '+5', Colors.white70);
            Sfx.tapLight();
          }
          break;
        }
      }
      // Bullets → boss
      final bss = boss;
      if (b.active && bss != null && bss.active) {
        if (_hit(b.x, b.y, kBulletW, kBulletH, bss.x, bss.y, kBossW, kBossH)) {
          b.active = false;
          bss.hp--;
          score += 100;
          if (score > highScore) highScore = score;
          _shakeT = 0.15;
          _addFloat(bss.x, bss.y - 20, '+100', Colors.yellow);
          if (bss.hp <= 0) _killBoss(bss);
        }
      }
    }

    // Mamlas → player
    if (!invincible && !shielded) {
      for (final m in mamlas) {
        if (!m.active) continue;
        if (_hit(m.x, m.y, kMamlaW, kMamlaH, playerX, playerY, kPlayerW, kPlayerH)) {
          m.active = false; _hitPlayer();
        }
      }
    }

    // Power-ups → player
    for (final p in powerUps) {
      if (!p.active) continue;
      if (_hit(p.x, p.y, kPowerUpSize, kPowerUpSize, playerX, playerY, kPlayerW + 12, kPlayerH + 12)) {
        p.active = false; _applyPow(p);
      }
    }

    // Enemies reach player row → instant game over
    for (final e in enemies) {
      if (!e.alive) continue;
      final (_, ey) = ePos(e);
      if (ey + eH / 2 >= playerY - kPlayerH / 2) {
        phase = GamePhase.gameOver; _saveHigh(); return;
      }
    }
  }

  bool _hit(double ax, double ay, double aw, double ah,
            double bx, double by, double bw, double bh) =>
      (ax - aw/2 < bx + bw/2) && (ax + aw/2 > bx - bw/2) &&
      (ay - ah/2 < by + bh/2) && (ay + ah/2 > by - bh/2);

  // ── Win check ────────────────────────────────────────────────────────────────

  void _checkWin() {
    if (phase == GamePhase.playing  && enemies.every((e) => !e.alive) ||
        phase == GamePhase.bossFight && (boss == null || !boss!.active)) {
      phase = GamePhase.levelComplete;
      _lvlDoneT = 2.4;
      _saveHigh(); // persist between levels so a kill/crash doesn't lose the record
      _addFloat(sw / 2, sh * .42, '✅ LEVEL $level CLEARED!', Colors.greenAccent);
    }
  }

  // ── Kill helpers ─────────────────────────────────────────────────────────────

  void _killEnemy(Enemy e, {bool viral = false}) {
    e.alive = false;
    final (ex, ey) = ePos(e);
    kills++;
    combo++; comboT = 2.0;
    final mul = combo >= 6 ? 4 : combo >= 4 ? 3 : combo >= 2 ? 2 : 1;
    final pts = e.points * mul;
    score += pts;
    if (score > highScore) highScore = score;
    viralCharge = (viralCharge + kViralPerKill).clamp(0, 1);
    fmSpeed = _calcFmSpeed();

    explosions.add(Explosion(ox: ex, oy: ey, label: mul > 1 ? 'x$mul!' : ''));
    _addFloat(ex, ey - 18, mul > 1 ? '+$pts ×$mul' : '+$pts', Colors.yellow);
    if (!viral) { Sfx.explosion(); Sfx.tapLight(); } // viral plays one big boom

    if (!viral && _rng.nextDouble() < 0.20) {
      final t = PowerUpType.values[_rng.nextInt(PowerUpType.values.length)];
      powerUps.add(PowerUp(x: ex + (_rng.nextDouble() - 0.5) * 16, y: ey, type: t));
    }
  }

  void _killBoss(Boss b) {
    b.active = false;
    kills++;
    score += 500; if (score > highScore) highScore = score;
    _shakeT = 1.0;
    Sfx.bigBoom(); Sfx.tapHeavy();
    for (int i = 0; i < 9; i++) {
      explosions.add(Explosion(
        ox: b.x + (_rng.nextDouble() - 0.5) * 80,
        oy: b.y + (_rng.nextDouble() - 0.5) * 40,
        label: i == 4 ? 'BOSS DOWN! +500' : '',
      ));
    }
    _addFloat(b.x, b.y - 10, '🎉 +500  BOSS JAILED!', Colors.greenAccent);
    for (int i = 0; i < 3; i++) {
      powerUps.add(PowerUp(
        x: b.x + (i - 1) * 44.0, y: b.y,
        type: PowerUpType.values[i % PowerUpType.values.length],
      ));
    }
  }

  void _hitPlayer() {
    lives--;
    invincible = true; invincT = kInvincibleDuration;
    _shakeT = 0.55;
    Sfx.explosion(); Sfx.tapMedium();
    _addFloat(playerX, playerY - 28, '📋 MAMLA HIT!', Colors.red);
    if (lives <= 0) { phase = GamePhase.gameOver; _saveHigh(); }
  }

  void _applyPow(PowerUp p) {
    Sfx.tapLight();
    switch (p.type) {
      case PowerUpType.shield:
        shielded = true; shieldT = 4.5;
        _addFloat(playerX, playerY - 30, '🛡️  SHIELD!', Colors.cyanAccent);
      case PowerUpType.multiShot:
        multiShot = true; multiShotT = 6.0;
        _addFloat(playerX, playerY - 30, '⚡ MULTI-SHOT!', Colors.yellow);
      case PowerUpType.slowMo:
        slowMo = true; slowMoT = 4.0;
        _addFloat(playerX, playerY - 30, '⏱️  SLOW-MO!', Colors.lightBlueAccent);
    }
  }

  void _addFloat(double x, double y, String text, Color c) =>
      floats.add(FloatingText(x: x, y: y, text: text, color: c));

  // ── Speed calc ───────────────────────────────────────────────────────────────

  double _calcFmSpeed() {
    // sqrt ramp + hard cap: the old linear (36/alive) ramp sent the last
    // enemy across the screen at ~1800 px/s — visually teleporting.
    final alive = max(1, enemies.where((e) => e.alive).length);
    final raw = kEnemyBaseSpeed * sqrt(kTotalEnemies / alive) * (1 + (level - 1) * 0.10);
    return min(raw, kFmMaxSpeed);
  }

  // ── High score ───────────────────────────────────────────────────────────────

  Future<void> _loadHigh() async {
    final p = await SharedPreferences.getInstance();
    if (_disposed) return; // engine may be gone before the async load resolves
    highScore = p.getInt('mamla_high') ?? 0;
    notifyListeners();
  }

  Future<void> _saveHigh() async {
    if (score >= highScore) {
      final p = await SharedPreferences.getInstance();
      await p.setInt('mamla_high', highScore);
    }
  }
}
