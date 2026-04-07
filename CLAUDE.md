# Cortex

Terminal mission control for multi-project developers. Browser-based dashboard for managing concurrent terminal sessions via Phoenix LiveView + xterm.js. Each terminal is a GenServer wrapping a real PTY via ExPTY.

**Product:** Local-first app with cloud auth/billing. Runs on user's machine, terminals stay local.

## Quick Start

```bash
mix setup          # deps, db, assets
mix phx.server     # http://localhost:3012
```

## Architecture

**Contexts:**

- `Accounts` -- users, authentication, sessions, license tiers
- `Terminals` -- session CRUD, lifecycle management, layout persistence, crash recovery
- `Projects` -- project registry, user-configured projects, presets, workspaces
- `Intelligence` -- priority scoring, daily brief, output monitoring
- `Workspaces` -- named workspace save/restore

**OTP Processes:**

- `Terminal.SessionSupervisor` -- DynamicSupervisor for session GenServers
- `Terminal.SessionServer` -- one GenServer per PTY session (wraps ExPTY)
- `Terminal.SessionRegistry` -- Registry for session lookup by ID
- `Projects.Registry` -- GenServer, loads projects from DB (+ optional CLAUDE.md fallback)
- `Intelligence.Prioritizer` -- GenServer, scans projects every 5m, ranks by score
- `Intelligence.OutputMonitor` -- GenServer, watches terminal output for patterns

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
- xterm.js + @xterm/addon-fit + @xterm/addon-webgl + @xterm/addon-search

## Conventions

- Phoenix contexts for all business logic (never in LiveView)
- Pattern match over if/else
- Pipe operator for data transformations
- All data scoped to current user (multi-tenant ready)
- Tests mirror lib/ structure

## Theme

Amber/gold CRT aesthetic:
- Background: #050505
- Accent: #ffd04a
- Text: #e8dcc0
- Muted: #3a3a3a, #5a5a5a
- Error: #e05252, Success: #5ea85e, Info: #5a9bcf
- Border: #1a1a1a, radius: 6-8px
- No glow, no glass morphism

## Key Files

- `lib/cortex/terminal/session_server.ex` -- GenServer per PTY session (core)
- `lib/cortex_web/live/dashboard_live/index.ex` -- Main grid dashboard
- `assets/js/hooks/terminal_hook.js` -- xterm.js <-> LiveView bridge
- `assets/js/hooks/command_palette_hook.js` -- Keyboard shortcuts
- `assets/js/hooks/drag_hook.js` -- Terminal reordering
- `assets/js/terminal/theme.js` -- Amber/gold CRT theme
- `lib/cortex/intelligence/prioritizer.ex` -- Project priority scoring
- `lib/cortex/intelligence/output_monitor.ex` -- Terminal output pattern detection
- `lib/cortex/intelligence/daily_brief.ex` -- Daily action briefing
- `lib/cortex/workspaces.ex` -- Workspace save/restore
- `lib/cortex/projects/git_status.ex` -- Git status per project
- `lib/cortex/application.ex` -- OTP supervision tree + orphan cleanup

## Completed (Phases 1-5)

- [x] Scrollback persistence to disk (30s flush + restore)
- [x] Graceful shutdown with PTY cleanup
- [x] Output Monitor with pattern detection (errors, tests, deploys, git, Claude)
- [x] Toast notifications + session status badges
- [x] Named workspaces with save/restore/auto-launch
- [x] Terminal search (Ctrl+Shift+F)
- [x] Drag-and-drop terminal reordering
- [x] Copy mode (Ctrl+Shift+C)
- [x] Deploy status widget + git status per project
- [x] Quick actions in command palette

## Product Roadmap

### Phase 7: Auth & User Model
- [ ] User schema (email, name, tier, api_token)
- [ ] Magic link authentication (email + token, no passwords)
- [ ] Session management (Phoenix.Token)
- [ ] Auth plugs + LiveView on_mount hooks
- [ ] Login/register pages with CRT theme
- [ ] License tiers: free (3 projects, 3 sessions) / pro (unlimited)

### Phase 8: Project Config UI
- [ ] Replace CLAUDE.md parsing with DB-backed project config
- [ ] Project setup page: add/edit/remove projects
- [ ] Auto-detect project type (mix.exs, package.json, Cargo.toml, etc.)
- [ ] User-configurable priority weights (not hardcoded revenue tiers)
- [ ] Settings page for preferences
- [ ] Keep CLAUDE.md as optional import source

### Phase 9: Onboarding Wizard
- [ ] First-run detection (no projects configured)
- [ ] Step-by-step project setup: scan filesystem for git repos
- [ ] Suggest dev commands based on project type
- [ ] Quick workspace creation from selected projects
- [ ] Welcome brief on first login

### Phase 10: Landing Page & Waitlist
- [ ] Marketing landing page at / (unauthenticated)
- [ ] Dashboard at /dashboard (authenticated)
- [ ] Email waitlist capture (store in DB)
- [ ] Feature showcase with screenshots/GIFs
- [ ] CRT-themed design matching the app

### Phase 11: Stripe Billing
- [ ] Stripe products: free / pro ($19/mo)
- [ ] Customer portal for subscription management
- [ ] Webhook handler for payment events
- [ ] Feature gating based on tier
- [ ] Trial period (14 days pro)

### Phase 12: Distribution
- [ ] Homebrew formula
- [ ] Docker image
- [ ] One-line install script
- [ ] Auto-update mechanism
- [ ] Fly.io deploy config for cloud components

## Agent Team

**Team Lead:** Architect

Product agents:

- **cortex-auth** -- Authentication, user model, session management, license tiers
- **cortex-config** -- Project config UI, settings, DB-backed registry, auto-detect
- **cortex-onboard** -- First-run wizard, project scanning, welcome flow
- **cortex-landing** -- Marketing page, waitlist, feature showcase
- **cortex-billing** -- Stripe integration, tier gating, webhooks

Core agents (existing):

- **cortex-pty** -- PTY spawning, ExPTY integration, session GenServer, scrollback
- **cortex-ui** -- LiveView dashboard, xterm.js hooks, grid layout, theming
- **cortex-projects** -- Project registry, preset system, workspace management
- **cortex-intel** -- Intelligence engine, output monitoring, pattern detection, notifications
- **cortex-monitor** -- Health checks, process monitoring, crash recovery, metrics

## Pricing

| Tier | Price | Projects | Sessions | Features |
|------|-------|----------|----------|----------|
| Free | $0 | 3 | 3 | Basic terminal grid, command palette |
| Pro | $19/mo | Unlimited | Unlimited | Workspaces, intelligence, output monitoring, priority engine |
| Team | $39/seat/mo | Unlimited | Unlimited | Shared workspaces, session streaming (future) |

## Port

Dev server: localhost:3012
