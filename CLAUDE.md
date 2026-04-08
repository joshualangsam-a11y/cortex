# Cortex

Terminal mission control for multi-project developers. Built by a neurodivergent founder for how real brains actually work. Browser-based dashboard for managing concurrent terminal sessions via Phoenix LiveView + xterm.js. Each terminal is a GenServer wrapping a real PTY via ExPTY.

**Product:** Local-first app with cloud auth/billing. Runs on user's machine, terminals stay local.
**Positioning:** "Built for brains that don't wait." Neurodivergent-native design as structural moat.

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
- `Intelligence` -- priority scoring, daily brief, output monitoring, momentum, thermal throttle, session DNA
- `Workspaces` -- named workspace save/restore
- `NDProfile` -- neurodivergent cognitive profile (thinking style, energy cycle, flow tuning)

**OTP Processes:**

- `Terminal.SessionSupervisor` -- DynamicSupervisor for session GenServers
- `Terminal.SessionServer` -- one GenServer per PTY session (wraps ExPTY)
- `Terminal.SessionRegistry` -- Registry for session lookup by ID
- `Projects.Registry` -- GenServer, loads projects from DB (+ optional CLAUDE.md fallback)
- `Intelligence.Prioritizer` -- GenServer, scans projects every 5m, ranks by score
- `Intelligence.OutputMonitor` -- GenServer, watches terminal output for patterns
- `Intelligence.MomentumEngine` -- GenServer, tracks keystroke velocity, detects flow state
- `Intelligence.SessionDNA` -- GenServer, fingerprints session activity types
- `Intelligence.ThermalThrottle` -- GenServer, detects cognitive overload from error/velocity correlation

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
- `lib/cortex/intelligence/daily_brief.ex` -- Daily action briefing (energy-aware)
- `lib/cortex/intelligence/momentum_engine.ex` -- Flow state detection from keystroke velocity
- `lib/cortex/intelligence/resume_point.ex` -- Zeigarnik resume hooks on session exit
- `lib/cortex/intelligence/flow_history.ex` -- Flow session persistence + streak tracking
- `lib/cortex/intelligence/energy_cycle.ex` -- Time-of-day energy phase detection
- `lib/cortex/intelligence/session_dna.ex` -- Activity fingerprinting per session
- `lib/cortex/intelligence/thermal_throttle.ex` -- Cognitive overload detection
- `lib/cortex/terminals/burst_mode.ex` -- Parallel session launcher per project type
- `lib/cortex/nd_profile.ex` -- Neurodivergent cognitive profile (configurable)
- `lib/cortex/workspaces.ex` -- Workspace save/restore
- `lib/cortex/projects/git_status.ex` -- Git status per project
- `lib/cortex/application.ex` -- OTP supervision tree + orphan cleanup

## Neurodivergent-Native Design (The Moat)

Cortex is designed for brains that think in parallel, not linear. Every feature listed
below is a structural architectural decision, not a cosmetic add-on.

**Momentum Engine** -- Tracks keystroke velocity across sessions. Detects flow state when
sustained input exceeds threshold for 30+ seconds. Broadcasts via PubSub so the entire
UI reacts: toast suppression, amber flow indicator, context switch guard.

**Flow Guard** -- During flow state, Cmd+K shows "You're in flow — switch anyway?" with
a 1-second gate. Not blocking — just making the cost of context-switching visible.
Based on: "flow interrupts accumulate as headaches."

**Zeigarnik Resume Points** -- On session exit, analyzes last 2KB of output to detect
what was happening (compile errors, test failures, Claude agents, deploys). Generates
"context + next action" pairs shown on next launch. Exploits Zeigarnik Effect to
maintain momentum across sessions.

**Energy Cycle Awareness** -- Knows mud hours (6-11am) vs peak hours (2-10pm). Adjusts
daily brief greeting, suggests lighter tasks during mud, queues deep work for peak.

**Thermal Throttle** -- Correlates error rate, velocity drops, context-switch frequency,
and session duration. When signals cross threshold: "Brain overheating — not quitting,
just thermal throttling." Based on: "Wall = headache, not quitting."

**Burst Mode** -- One keypress spawns full project context (server, tests, agent).
Designed for parallel-processing brains that need all threads running at once.
Based on: "Needs multiple parallel tracks or gets bored and stalls."

**Session DNA** -- Fingerprints each session with activity types (build, test, deploy,
debug, flow, agent). Powers "today you spent 3h building, 45m debugging."

**Attack-Surface Error UI** -- Errors reframed from passive ("Build failed") to
action-oriented ("build broke — attack it") with action hints ("scroll up for root cause").
Based on: "Suffering is fuel" + "Failure doesn't exist."

**Flow History** -- Persists flow sessions with streak tracking. Evidence for when
self-doubt hits: "You've logged 14 hours of flow this week across 23 sessions."

**ND Profile** -- Configurable cognitive profile: thinking style, energy cycle, flow
thresholds, context-switch cost, interruption tolerance. Presets for ADHD-Parallel,
ADHD-Hyperfocus, Autism-Systematic, Dyslexia-Visual, Neurotypical.

## Completed (Phases 1-6)

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
- [x] Phase 6: Neurodivergent-Native Design
  - [x] MomentumEngine (flow detection from keystroke velocity)
  - [x] Zeigarnik Resume Points (resume_points table + output analysis)
  - [x] FlowHistory (flow_sessions table + streak tracking)
  - [x] EnergyCycle (time-of-day energy phase awareness)
  - [x] ThermalThrottle (cognitive overload detection)
  - [x] SessionDNA (activity fingerprinting)
  - [x] BurstMode (parallel session launcher)
  - [x] NDProfile (nd_profiles table + configurable cognitive profile)
  - [x] Attack-surface error reframing (OutputPatterns + Notification)
  - [x] Flow-aware toast suppression
  - [x] Context switch guard (JS flow gate)
  - [x] Energy-aware daily brief greetings
  - [x] Flow state CSS animations
  - [x] Header indicators (energy, momentum, flow time)

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
