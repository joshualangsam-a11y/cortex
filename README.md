# Cortex ND

An intelligent terminal orchestration layer built for neurodivergent developers. Cortex watches how you work — your energy cycles, momentum patterns, and flow states — then adapts your environment in real time.

This isn't a productivity tool. It's a cognitive co-processor.

## What It Does

Cortex runs 21+ intelligence modules as concurrent Elixir processes, each observing a different dimension of your work:

| Module | What It Watches |
|--------|----------------|
| **Energy Cycle** | Maps your ultradian rhythms to suggest when to push vs. rest |
| **Flow Calibrator** | Detects flow state entry/exit and protects deep work |
| **Thermal Throttle** | Monitors cognitive load and warns before burnout |
| **Momentum Engine** | Tracks task completion velocity and compounds streaks |
| **Crash Predictor** | Identifies patterns that precede productivity crashes |
| **Intent Compression** | Reduces context-switching overhead between projects |
| **Session Architect** | Designs optimal work sessions based on your history |
| **Token Economics** | Tracks AI token usage and optimizes prompt efficiency |
| **Entropy Detector** | Flags when you're thrashing vs. making progress |
| **Daily Brief** | Generates a morning briefing from overnight changes |

Plus 11 more modules for pattern detection, output monitoring, priority scoring, and session DNA fingerprinting.

## Architecture

Built on Elixir/OTP for fault-tolerant concurrency. Each intelligence module runs as a supervised GenServer — if one crashes, the rest keep running.

```
cortex/
├── lib/
│   ├── cortex/
│   │   ├── intelligence/       # 21 intelligence modules
│   │   │   ├── energy_cycle.ex
│   │   │   ├── flow_calibrator.ex
│   │   │   ├── thermal_throttle.ex
│   │   │   ├── momentum_engine.ex
│   │   │   ├── crash_predictor.ex
│   │   │   └── ...
│   │   ├── terminals/          # Terminal session management
│   │   │   ├── session.ex
│   │   │   ├── layout.ex
│   │   │   ├── preset.ex
│   │   │   └── burst_mode.ex
│   │   └── intelligence.ex     # Supervisor for all modules
│   └── cortex_web/             # Phoenix web interface
├── config/
├── priv/
└── test/
```

## Neurodivergent-Native Design

Every feature is a structural architectural decision, not a cosmetic add-on:

- **Flow Guard** — During detected flow state, context switches require a 1-second confirmation gate
- **Zeigarnik Resume Points** — On session exit, captures what you were doing and generates "context + next action" pairs for your next launch
- **Thermal Throttle** — Correlates error rate, velocity drops, and session duration to detect cognitive overload before you hit a wall
- **Burst Mode** — One keypress spawns full project context (server, tests, agent) for parallel-processing brains
- **Session DNA** — Fingerprints each session by activity type, powering insights like "today: 3h building, 45m debugging"
- **Attack-Surface Errors** — Errors reframed from passive ("Build failed") to action-oriented ("build broke — attack it")

## Built With

- [Elixir](https://elixir-lang.org/) / [Phoenix](https://www.phoenixframework.org/) — Concurrent, fault-tolerant runtime
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/) — Real-time UI
- [xterm.js](https://xtermjs.org/) — Terminal rendering
- [ExPTY](https://github.com/cocoa-xu/ex_pty) — Real PTY via forkpty NIF
- PostgreSQL — Session and profile persistence

## Run Locally

```bash
mix setup
mix phx.server
# http://localhost:4000
```

## Related Projects

- [neurodivergent-founders-os](https://github.com/joshualangsam-a11y/neurodivergent-founders-os) — Python framework for neurodivergent workflows
- [digital-twin](https://github.com/joshualangsam-a11y/digital-twin) — Cognitive architecture that thinks in parallel
- [bandwidth-expander-model](https://github.com/joshualangsam-a11y/bandwidth-expander-model) — The research paper behind this system

## License

MIT — see [LICENSE](LICENSE).
