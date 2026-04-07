# Cortex

Terminal session orchestrator. Browser-based dashboard for managing 8-9 concurrent terminal sessions via Phoenix LiveView + xterm.js. Each terminal is a GenServer wrapping a real PTY via ExPTY.

## Quick Start

```bash
mix setup          # deps, db, assets
mix phx.server     # http://localhost:3012
```

## Architecture

**Contexts:**

- `Terminals` -- session CRUD, lifecycle management
- `Projects` -- project registry (parses ~/CLAUDE.md), presets

**OTP Processes:**

- `Terminal.SessionSupervisor` -- DynamicSupervisor for session GenServers
- `Terminal.SessionServer` -- one GenServer per PTY session (wraps ExPTY)
- `Terminal.SessionRegistry` -- Registry for session lookup by ID
- `Projects.Registry` -- GenServer, loads project table from ~/CLAUDE.md at boot

**Data Flow:**

```
PTY -> SessionServer GenServer -> PubSub -> LiveView -> push_event -> JS hook -> xterm.js
```

Terminal output NEVER stored in LiveView assigns. Uses push_event to bypass diff engine.

## Stack

- Elixir ~1.15, Phoenix ~1.8.5, LiveView ~1.1.0
- PostgreSQL via Ecto (binary UUIDs, UTC timestamps)
- Tailwind v4, esbuild, Bandit
- ExPTY (real PTY via forkpty NIF)
- MuonTrap (orphan process prevention)
- xterm.js + @xterm/addon-fit + @xterm/addon-webgl

## Conventions

- Phoenix contexts for all business logic (never in LiveView)
- Pattern match over if/else
- Pipe operator for data transformations
- No auth -- local dev tool
- Tests mirror lib/ structure

## Key Files

- `lib/cortex/terminal/session_server.ex` -- GenServer per PTY session (core)
- `lib/cortex_web/live/dashboard_live/index.ex` -- Main grid dashboard
- `assets/js/hooks/terminal_hook.js` -- xterm.js <-> LiveView bridge
- `assets/js/terminal/theme.js` -- Amber/gold CRT theme

## Port

Dev server: localhost:3012

## Agent Team

**Team Lead:** Operator

Sub-agents:

- **cortex-pty** -- PTY spawning, ExPTY integration, session GenServer, scrollback
- **cortex-ui** -- LiveView dashboard, xterm.js hooks, grid layout, theming
- **cortex-projects** -- Project registry, preset system, command palette
- **cortex-deploy** -- Fly.io config, releases, Docker
