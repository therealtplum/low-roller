🎲 Low Roller

Low Roller is a fast, turn-based dice game where 3s count as zero.
Play head-to-head or against smart bots, build streaks, and climb the leaderboard.
Designed for quick offline matches with rich SwiftUI animations and an expandable architecture for online play.

⸻

🧩 Overview

Low Roller began as a cross-platform Rust + web prototype and has since evolved into a native SwiftUI iOS app featuring:
	
  • Smart bots with adjustable difficulty (Amateur / Pro)
	
  •	Persistent leaderboard (tracks dollars won, win streaks, and total wins)
	
  •	Turn timer with per-turn countdowns and fallback logic
	
  •	Confetti and animations for wins and sudden death rolls
	
  •	Automatic persistence of player names, wagers, and last setup
	
  •	Modular game engine (GameEngine.swift) for deterministic game logic
	
  •	Dynamic UI — Pre-Game lobby, Leaderboard tabs, and In-Game action bar
	
  •	Replay and reset support for quick rematches

⸻

📱 iOS App

Run in Xcode

open LowRoller.xcodeproj

Target: LowRoller
Framework: SwiftUI + Combine
Minimum iOS: 16.0

⸻

Key Source Files


File	Purpose

GameView.swift	Core in-game interface

PreGameView.swift	Lobby and player setup

LeaderboardStore.swift	Persistent stats and storage

SeatCfg.swift	Player/bot configuration model

LeaderRow.swift	Leaderboard display rows

⸻

Features
	
  •	Offline “hot-seat” local play (you + bots)
	
  •	Persistent stats across sessions
	
  •	Supports up to 8 seats (any mix of human/bot players)
	
  •	Smooth transitions and tap/swipe interactions
	
  •	Built-in debug and preview modes in Xcode

⸻

🧠 Architecture

Layer	Description

GameEngine.swift	Core turn logic, dice rolls, sudden death handling

LeaderboardStore.swift	Codable store for persistent player data

SwiftUI Views	Modular UI built around GameView and PreGameView

BotController.swift	Decision logic for AI turns

Rust Engine (optional)	Original deterministic logic, replaceable with WASM bindings later


⸻

🧰 Development Notes

Reset Leaderboard
In Xcode’s debug console:

LeaderboardStore().resetAll()

Preview UI
Use SwiftUI previews or run:

Cmd + Option + P

Debug

Open Console → ⌘ + ⇧ + C for runtime logs and state tracing.

⸻

🌐 Roadmap

Phase	Goal

v0.5	Offline iOS build with bots + leaderboard

v0.6	Dice animation and sudden-death visual roll

v0.7	SQLite persistence + shareable stats

v1.0	LAN rooms via WebSocket (Axum host)

Future	Cross-platform WASM + TestFlight rollout


⸻

🧪 Beta Testing

To join the TestFlight beta, contact the developer or join via invite link once available.

⸻

📂 Legacy Folders (from original prototype)

Path	Description

/engine/	Rust core (deterministic dice logic)

/engine-wasm/	Planned WebAssembly bindings

/web/	Original Vite + React client (prototype UI)

/host/	Axum WebSocket scaffold for multiplayer rooms


⸻

👤 Author

Thomas Plummer
GitHub @therealtplum
