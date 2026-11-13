# Marble Pop Factory (iOS)

Native iOS port of the Android game in `/Volumes/Work/Raj/Android/MarbelShort`.
This folder is a complete, independent Xcode project. It shares nothing with the other games.

| | |
|---|---|
| Bundle ID | `com.puzzel.lab.marbelshort` |
| Platform | iPhone, iOS 17+ |
| Status | **Port in progress.** Currently a placeholder screen. |

## Run it
1. Open `MarblePop.xcodeproj` in Xcode.
2. Pick an iPhone simulator (or your iPhone) and press **Run**.
3. For the App Store: in *Signing & Capabilities*, choose your Team once.

## What's inside
- `MarblePop/`: app code, art, sounds (`Resources/Audio`, 48 kHz), fonts, icon.
- `MarblePopTests/`: unit tests, including "same level as Android" checks.
- `Packages/GameKit/`: this game's own copy of the engine code (sound, haptics, saving, game loop, exact Android random numbers).
- `Reference/Android/`: screenshots of the Android version, used to compare the look.

## Port plan
- **Game.** Tap a bottom-connected block. Its 9 marbles pour through a hopper (Verlet physics) onto a looping belt and into the cup columns.
  - 5,000 levels (1–30 handmade). 12 special blocks unlocking at levels 6 → 120.
  - 4 boosters, 7 skins, 5 themes. Lucky Wheel, 7-day login, free gift every 4 h, chests, achievements, lucky ×2/×3/×5 needle.
- **Port.**
  - Engine: `GameEngine`, `Board` and `LevelGenerator` → Swift. Verlet: 3 substeps plus the anti-jam nudge. Belt path s → point.
  - Art: 3 static layers baked to images; moving sprites from a `SpriteCache`. The `MachineArt` "Candy Glass Machine" art is ported line by line.
  - Board shape: a union of rounded rectangles with corner smoothing, also used as the clip.
  - Audio: 21 WAVs re-rendered at 48 kHz, keeping the per-sound minimum gap.
- **Must match.** `java.util.Random` generator plus Kotlin `shuffled`. The 5,000-level solver test must pass.
- **Screens.** Splash → Onboarding (4 pages, no skip) → dock: Shop | Daily | **PLAY** map | Collection | Profile.
  - Settings → Legal.
  - Game popups: Intro "New!", Pause, Win, Fail (continue for 150 coins), Buy.
- **Simulator pass.**
  - A level introducing each special block (6, 8, 11, 15, 20, 25, 30, 40, 55, 70, 90, 120), a belt jam → revive, and a boss level (50).
  - Wheel spin and login reward.

## Upgrades over Android
- **Fixes:** —
- **New features** (`MarblePop/Extras/`, each behind a flag in `Extras/Features.swift`): colour-blind symbols on marbles, cups and blocks (Settings › Accessibility); Core Haptics synced to marbles landing in the cups; cup bounce spring and shimmer on filled cups.
