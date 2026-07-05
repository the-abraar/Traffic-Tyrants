import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game/audio.dart';
import '../game/game_engine.dart';
import '../game/game_painter.dart';
import '../game/entities.dart';
import 'game_over_screen.dart';
import 'menu_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late GameEngine _engine;
  late AnimationController _animCtrl;
  bool _started = false;
  bool _navigating = false;

  // Raw pointer tracking (Listener instead of GestureDetector: gesture-arena
  // competition made hold-to-move unresponsive until the finger dragged).
  final Map<int, Offset> _pointers = {};
  final Map<int, (Offset, Duration)> _downInfo = {};

  // Keyboard state (desktop/web) — merged with touch zones in _syncInput.
  bool _kbLeft = false, _kbRight = false;
  bool _zoneLeft = false, _zoneRight = false;

  @override
  void initState() {
    super.initState();
    _engine = GameEngine();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(hours: 1))
      ..repeat();
    _engine.addListener(_checkGameOver);
  }

  @override
  void dispose() {
    _engine.removeListener(_checkGameOver);
    _engine.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _checkGameOver() {
    if (_engine.phase == GamePhase.gameOver && mounted && !_navigating) {
      _navigating = true; // schedule navigation exactly once
      // Small delay so the last frame renders
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => GameOverScreen(engine: _engine)));
        }
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;
    final down = event is! KeyUpEvent;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _kbLeft = down; _syncInput(); return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _kbRight = down; _syncInput(); return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      if (k == LogicalKeyboardKey.space) {
        _engine.viralBlast(); return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.escape) {
        _engine.togglePause(); return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _goToMenu() {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MenuScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.viewPaddingOf(context).top;

    return PopScope(
      // Back button: first press pauses, second (while paused) exits to menu.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _engine.phase == GamePhase.gameOver) return;
        if (!_engine.paused) {
          _engine.togglePause();
        } else {
          _goToMenu();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // Start engine once we know the screen size
          if (!_started && w > 0 && h > 0) {
            _started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _engine.start(this, w, h, topPad: topPad);
            });
          } else if (_started) {
            _engine.resize(w, h); // no-op unless the window actually changed
          }

          return Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _pointers[e.pointer] = e.localPosition;
              _downInfo[e.pointer] = (e.localPosition, e.timeStamp);
              _updateZones(w);
            },
            onPointerMove: (e) {
              _pointers[e.pointer] = e.localPosition;
              _updateZones(w);
            },
            onPointerUp: (e) => _endPointer(e, w, checkSwipe: true),
            onPointerCancel: (e) => _endPointer(e, w),
            child: Stack(children: [
              // Game canvas
              AnimatedBuilder(
                animation: _animCtrl,
                builder: (_, __) => CustomPaint(
                  painter: GamePainter(_engine, _animCtrl.value * 3600),
                  size: Size(w, h),
                ),
              ),
              // Touch zone indicators (semi-transparent)
              Positioned(
                bottom: 0, left: 0,
                child: _ControlHint(icon: '◀', label: 'LEFT', w: w * 0.42, h: 110),
              ),
              Positioned(
                bottom: 0, right: 0,
                child: _ControlHint(icon: '▶', label: 'RIGHT', w: w * 0.42, h: 110),
              ),
              Positioned(
                bottom: 0,
                left: w * 0.42,
                width: w * 0.16,
                height: 110,
                child: _ViralHint(engine: _engine),
              ),
              // Pause button (below the HUD, clear of the BEST readout)
              Positioned(
                top: topPad + 58, right: 4,
                child: IconButton(
                  icon: const Icon(Icons.pause_rounded, color: Colors.white24, size: 26),
                  onPressed: _engine.togglePause,
                ),
              ),
              // Pause overlay
              ListenableBuilder(
                listenable: _engine,
                builder: (_, __) => _engine.paused
                    ? _PauseOverlay(onResume: _engine.togglePause, onMenu: _goToMenu)
                    : const SizedBox.shrink(),
              ),
            ]),
          ));
        },
      ),
    ));
  }

  void _endPointer(PointerEvent e, double w, {bool checkSwipe = false}) {
    final down = _downInfo.remove(e.pointer);
    _pointers.remove(e.pointer);
    _updateZones(w);
    // Swipe up = viral blast
    if (checkSwipe && down != null) {
      final dy = down.$1.dy - e.localPosition.dy;
      final ms = (e.timeStamp - down.$2).inMilliseconds;
      if (dy > 70 && ms > 0 && ms < 400) _engine.viralBlast();
    }
  }

  void _updateZones(double w) {
    _zoneLeft = false; _zoneRight = false;
    for (final p in _pointers.values) {
      if (p.dx < w * 0.42) _zoneLeft = true;
      if (p.dx > w * 0.58) _zoneRight = true;
    }
    _syncInput();
  }

  void _syncInput() {
    _engine.onLeft(_zoneLeft || _kbLeft);
    _engine.onRight(_zoneRight || _kbRight);
  }
}

// ── Pause overlay ─────────────────────────────────────────────────────────────
class _PauseOverlay extends StatefulWidget {
  final VoidCallback onResume, onMenu;
  const _PauseOverlay({required this.onResume, required this.onMenu});
  @override
  State<_PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<_PauseOverlay> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⏸️', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 8),
          const Text('PAUSED', style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w900,
              color: Colors.white, letterSpacing: 4)),
          const SizedBox(height: 28),
          _PauseBtn(label: '▶  RESUME', color: Colors.orange.shade700, onTap: widget.onResume),
          const SizedBox(height: 12),
          _PauseBtn(
            label: Sfx.enabled ? '🔊  SOUND ON' : '🔇  SOUND OFF',
            color: Colors.blueGrey.shade700,
            onTap: () => setState(() => Sfx.enabled = !Sfx.enabled),
          ),
          const SizedBox(height: 12),
          _PauseBtn(label: '🏠  MAIN MENU', color: Colors.blueGrey.shade800, onTap: widget.onMenu),
        ],
      ),
    );
  }
}

class _PauseBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PauseBtn({required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              color: Colors.white, letterSpacing: 1.2)),
    ),
  );
}

// ── Left / Right zone hint ────────────────────────────────────────────────────
class _ControlHint extends StatelessWidget {
  final String icon, label;
  final double w, h;
  const _ControlHint({required this.icon, required this.label, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white.withValues(alpha: 0.04)],
        ),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 28)),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 9, letterSpacing: 2)),
        ],
      ),
    );
  }
}

// ── Viral blast centre hint ───────────────────────────────────────────────────
class _ViralHint extends StatelessWidget {
  final GameEngine engine;
  const _ViralHint({required this.engine});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (_, __) {
        final ready = engine.viralCharge >= 1.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(ready ? '🔥' : '○', style: TextStyle(
              fontSize: ready ? 28 : 14,
              color: ready ? Colors.orange : Colors.white24)),
            Text('VIRAL', style: TextStyle(
              color: ready ? Colors.orange.withValues(alpha: 0.8) : Colors.white12,
              fontSize: 8, letterSpacing: 1.5,
              fontWeight: FontWeight.w700)),
            Text('↑ swipe', style: TextStyle(
              color: ready ? Colors.orange.withValues(alpha: 0.6) : Colors.white12,
              fontSize: 7)),
          ],
        );
      },
    );
  }
}
