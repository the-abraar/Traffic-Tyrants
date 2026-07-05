# 🏍️ Mamla Invaders

> The corrupt traffic sergeants of Bangladesh have taken to the skies — and they're raining **mamlas** (court cases 📋) on every biker below. Grab your helmet. Your honk is your weapon.

A fast, juicy, emoji-powered Space Invaders built **entirely with Flutter's Canvas** — no game engine, no sprite sheets, just `CustomPainter`, math, and attitude. Runs on Android, iOS, desktop, and web from a single codebase.

<p align="center">
  <em>😤 😠 🤬 — the formation sways, drops, and throws paperwork at you — 📋📋📋</em>
</p>

## Why you'll get hooked

- **Combo multipliers** — chain kills within 2 seconds for ×2/×3/×4 score. Greed is the meta.
- **🔥 Viral Blast** — every ~11 kills charges a swipe-up super that wipes the two closest rows, or slams the boss for massive damage. Save it or spend it?
- **👿 Boss every 3rd wave** — the Super Inspector strafes, bobs, and fires 3-way mamla spreads. His HP grows every visit.
- **Power-ups** — 🛡️ shield, ⚡ triple-shot, ⏱️ slow-mo (bullet-time for everything except *you*).
- **Enemy personalities** — 😤 constables drop straight, 😠 sergeants *lead their throws at you*, 🤬 inspectors take two hits and flash white when clipped.
- **Feel** — screen shake, particle explosions, floating score text, engine haptics, honk-blast sound effects, and a per-wave countdown so you're never ambushed.

## Controls

| Platform | Move | Viral Blast | Pause |
|----------|------|-------------|-------|
| Touch | Hold left / right side of screen | Swipe up | ⏸ button (or Android back) |
| Keyboard | ← → or A / D | Space | P or Esc |

Firing is automatic — positioning *is* the skill.

## Run it

```bash
git clone https://github.com/<you>/Chicken-Invaders-Clone.git
cd Chicken-Invaders-Clone
flutter pub get
flutter run          # or: flutter run -d chrome / -d windows / -d linux
```

Requires Flutter 3.x. That's it — no API keys, no backend, no nonsense.

## How it's built

The whole game is ~1,500 lines of Dart in a deliberately simple architecture:

```
lib/
├── main.dart                 # App bootstrap (portrait, immersive)
├── game/
│   ├── constants.dart        # Every tunable number in one place
│   ├── entities.dart         # Enemy, Boss, Bullet, Mamla, PowerUp, FX
│   ├── game_engine.dart      # Simulation: tick loop, physics, collisions, scoring
│   ├── game_painter.dart     # Rendering: one CustomPainter draws everything
│   └── audio.dart            # Pooled SFX + haptics
└── screens/
    ├── menu_screen.dart      # Animated title + marching sergeants
    ├── game_screen.dart      # Input (touch zones + keyboard), pause overlay
    └── game_over_screen.dart # Stats card + restart
```

Design notes worth stealing:

- **Engine and renderer never touch.** `GameEngine` is a pure `ChangeNotifier` simulation driven by a `Ticker` with delta-time (frame-rate independent). `GamePainter` just reads its state — you could swap the renderer for Flame or sprites without touching game logic.
- **Widgets rebuild only on transitions** (phase change, viral-ready), not 60×/s — the canvas has its own `AnimationController`.
- **TextPainter caching** with alpha quantization: emoji + text rendering is the hottest per-frame cost, so layouts are cached and evicted in halves to avoid hitches.
- **Every gameplay number lives in `constants.dart`** — rebalancing the whole game is a one-file edit.

## Contributing

PRs are very welcome — this codebase is small enough to read in one sitting, which makes it a great first Flutter-game contribution. Ideas up for grabs:

- 🎵 Background music + richer SFX (power-up, boss-warning stinger)
- 🌊 New enemy behaviors — divers that break formation, shielded rows, zig-zag mamlas
- 🏆 Online leaderboard, or local stats (games played, total mamlas dodged)
- 🎨 New bosses — the *DIG-site Excavator*? the *Ferry Ghat Extortionist*?
- 🌐 Bangla localization (the game begs for it)
- 📱 Landscape / tablet layout tuning
- ✅ Widget & engine unit tests (`GameEngine` is fully testable headless)

Workflow: fork → branch → `flutter analyze` clean → PR with a short clip or GIF of the change if it's visual.

## The lore

*Mamla* (মামলা) = a court case. In Dhaka traffic mythology, an unlucky biker can collect them like Pokémon. This game is affectionate satire — dodge the paperwork, jail the corrupt, go viral.

The repo also contains the game's ancestor: a weekend **pygame** prototype (`Main.py`, `src/`) that grew up into this Flutter app. It's kept for archaeology.

---

*"Every mamla has an end. Ride through it."* 🏍️💨
