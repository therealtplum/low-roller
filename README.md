# Low Roller — Starter

Turn-based dice game (3 counts as 0), v0 offline/hot-seat with replay and timer UI stubs.

## Quickstart (web client with **pnpm**)
```bash
cd web
pnpm i
pnpm dev
# open http://localhost:5173
```

You can roll, pick dice (must pick >=1), use "Timeout Fallback" to simulate the 5-min bot fallback, and view a JSON replay log.

## Structure
- `engine/` Rust core (deterministic logic)
- `web/` React + Vite client (JS engine stub for instant run; swap to WASM later)
- `host/` Axum WS scaffold (future LAN rooms)

## Next
- Build `engine-wasm/` and swap `web/src/game/engine.ts` import to use real WASM bindings.
- Add bots taking turns automatically, sudden death UI, SQLite persistence, LAN rooms.

- **iOS (SwiftUI)** — open `LowRoller.xcodeproj` (source in `LowRoller/`)
- **Desktop**
  - Rust engine → `LowRollerDesktop/engine`
  - Web UI     → `LowRollerDesktop/web`
