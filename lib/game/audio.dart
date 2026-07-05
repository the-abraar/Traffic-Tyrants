import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Fire-and-forget sound effects + haptics.
///
/// A small round-robin pool of [AudioPlayer]s so overlapping effects
/// (rapid kills, boss barrage) don't cut each other off. Every call is
/// wrapped in try/catch: audio must never crash the game.
class Sfx {
  Sfx._();

  static bool enabled = true;

  static const _poolSize = 6;
  static final List<AudioPlayer> _pool = [];
  static int _next = 0;

  static void _play(String asset, double volume) {
    if (!enabled) return;
    try {
      if (_pool.length < _poolSize) {
        _pool.add(AudioPlayer()..setReleaseMode(ReleaseMode.stop));
      }
      final p = _pool[_next++ % _pool.length];
      p.stop();
      p.play(AssetSource('audio/$asset'), volume: volume);
    } catch (_) {/* missing asset / platform without audio — ignore */}
  }

  // ── Sounds ──────────────────────────────────────────────────────────────────
  static void shot()      => _play('shot.wav', 0.25);
  static void explosion() => _play('explosion.wav', 0.55);
  static void bigBoom()   => _play('explosion.wav', 1.0);

  // ── Haptics (no-ops on platforms without a vibrator) ────────────────────────
  static void tapLight()  { try { HapticFeedback.lightImpact();  } catch (_) {} }
  static void tapMedium() { try { HapticFeedback.mediumImpact(); } catch (_) {} }
  static void tapHeavy()  { try { HapticFeedback.heavyImpact();  } catch (_) {} }

  static Future<void> dispose() async {
    for (final p in _pool) {
      try { await p.dispose(); } catch (_) {}
    }
    _pool.clear();
    _next = 0;
  }
}
