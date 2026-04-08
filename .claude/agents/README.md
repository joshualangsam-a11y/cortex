# Cortex Agent Team

These agents operationalize the Bandwidth Expander Model (BEM) — the neuroscience and architecture behind Cortex. Each agent understands the theory AND builds the features.

## The Bandwidth Expander Model (BEM)

Cortex expands cognitive bandwidth for neurodivergent developers through 11 mechanisms:

1. **Intent Compression/Decompression** — One keystroke → full project context
2. **Momentum Preservation** — Velocity flows across context switches
3. **Parallel Track Support** — Multiple concurrent sessions without overload
4. **Error Absorption** — Reframe errors as attack vectors
5. **Memory Externalization** — Working memory dumps to disk
6. **Divergent-Convergent Spiral** — Context-switching guard preserves flow
7. **Cognitive Thermal Management** — Detect when brain overheats
8. **Cross-Session Compounding** — Evidence that you're getting smarter
9. **Metacognitive Computation** — Make brain state visible
10. **Parallel Processing as Thermal Management** — Cool off by switching domains
11. **Theory-Building as Bandwidth Mechanism** — Pattern recognition becomes automatic

## Agent Ownership

Each agent owns a subset of mechanisms and the features that implement them.

### [cortex-bandwidth.md](cortex-bandwidth.md)
**Mechanisms:** 1, 2, 4, 5, 9

Builds the core bandwidth expansion features:
- **Intent Compression:** Burst mode (Cmd+Space spawns multi-session context)
- **Momentum Preservation:** Resume points, session snapshots, velocity indicators
- **Error Absorption:** Action-oriented error UI ("attack it" not "retry")
- **Memory Externalization:** Scrollback, session DNA, resume points
- **Metacognitive Computation:** Flow state + thermal state + energy visibility

**Key systems:**
- `BurstMode` — Multi-session intent launcher
- `ResumePoint` — Context snapshots on session exit
- `SessionDNA` — Activity fingerprinting
- `MomentumEngine` — Velocity tracking
- Dashboard indicators — Real-time brain state

**When to use:** Building resume points, burst mode, momentum indicators, error UI, scrollback search, session DNA.

---

### [cortex-thermal.md](cortex-thermal.md)
**Mechanisms:** 3, 7, 10

Builds thermal management (hormesis-aware stress detection):
- **Cognitive Thermal Management:** Detect overheating from error spikes, velocity drops, context thrashing, marathon sessions
- **Parallel Track Support:** Manage parallel capacity with thermal awareness
- **Parallel Processing as Thermal Management:** Cool off by domain-switching

**Key systems:**
- `ThermalThrottle` — Detect overheating from signal correlation
- `OutputMonitor` — Error rate tracking
- Thermal UI — Real-time thermal gradient + history dashboard
- Cooling suggestions — Relief based on thermal state + energy phase

**When to use:** Building thermal detection, thermal history dashboard, domain-switch suggestions, cooling period UI, thermal indicator animations.

---

### [cortex-flow.md](cortex-flow.md)
**Mechanisms:** 2, 6, 8

Builds flow state detection and protection:
- **Momentum Preservation:** Detect when velocity enters flow + broadcast it
- **Divergent-Convergent Spiral:** Context-switch guard ("You're in flow")
- **Cross-Session Compounding:** Flow streak tracking + evidence

**Key systems:**
- `MomentumEngine` — Flow detection from velocity sustain
- `FlowCalibrator` — Per-user flow threshold personalization
- `FlowHistory` — Persistence + streak tracking
- Flow indicators — Real-time meter + shield mode
- Context-switch guard — 1s delay gate when in flow

**When to use:** Building flow detection, flow indicators, flow shield mode, context-switch guard, flow history + streaks, flow calibration.

---

### [cortex-nd.md](cortex-nd.md)
**Mechanisms:** All (profile-based adaptation)

Builds the neurodivergent profile system (the moat):
- Per-user cognitive configuration (thinking style, energy cycle, flow thresholds, context-switch cost)
- Preset profiles (ADHD Parallel, ADHD Hyperfocus, Autism Systematic, Dyslexia Visual, Neurotypical)
- Profile-based UI adaptation (greetings, notifications, command organization, visual indicators)
- Onboarding wizard to discover user's brain

**Key systems:**
- `NDProfile` — Ecto schema + presets + current() caching
- Profile wizard — 5-page questionnaire with presets
- Settings page — Customization + live preview
- Profile-based adaptation — Greetings, notification frequency, energy visualization

**When to use:** Building profile onboarding, preset selection, profile settings page, energy timeline visualization, profile-based UI adaptation.

---

### [cortex-compound.md](cortex-compound.md)
**Mechanisms:** 8, 11

Builds cross-session compounding (pattern crystallization):
- **Cross-Session Compounding:** Evidence that developers compound (velocity trends, error recovery speedup, streak tracking)
- **Theory-Building as Bandwidth:** Pattern detection shows mastery development

**Key systems:**
- `SessionDNA` — Activity fingerprinting (shared, you own display)
- `Compound.Metrics` — Daily/weekly velocity trends, error recovery time
- `Compound.Pattern` — Recurring sequence detection + mastery leveling
- Compound dashboard — "You're smarter than yesterday" evidence
- Daily brief — Compounding insight cards

**When to use:** Building compound metrics, pattern detection, compound dashboard, pattern mastery visualization, daily brief evidence.

---

## Architecture Pattern

All agents follow this pattern:

### Theory → Code

Each agent file explains:
1. **The neuroscience** — Why this mechanism matters for ND brains
2. **The Elixir architecture** — Which GenServers, Ecto schemas, PubSub topics
3. **The LiveView patterns** — How UI subscribes to state changes
4. **The key files** — Which files live where
5. **The rules** — Pattern matching, contexts own logic, 5-stage pipes, etc

### Implementation Flow

```
GenServer (state management)
  ↓ PubSub broadcasts
    ↓ LiveView subscribes
      ↓ UI updates via assigns
        ↓ User interacts
          ↓ Back to GenServer
```

### Naming Convention

- **Mechanism #3** = Platform threads, thermal management
- **Mechanism #7** = ThermalThrottle GenServer
- **Mechanism #8** = CompoundMetrics + FlowHistory
- etc.

All mechanisms are interconnected. When one broadcasts, others react. The dashboard is the nervous system that makes all signals visible.

## How to Use These Agents

**Start with the team lead:**
`cortex-bandwidth` owns the core momentum + memory system. Most features touch bandwidth.

**Then specialize:**
- Need thermal management? → `cortex-thermal`
- Need flow protection? → `cortex-flow`
- Need profile customization? → `cortex-nd`
- Need compounding evidence? → `cortex-compound`

**All agents know:**
- The full BEM theory (so they understand why features matter)
- The Elixir/LiveView conventions (patterns, processes, supervision)
- The key existing files (where to hook in new features)
- The rules (no conditionals, contexts own logic, PubSub-driven)

## Key Insight: The Moat

Cortex's structural moat is NOT a feature — it's the model. Other tools have notifications, command palettes, debugging. Cortex asks: **"What does THIS brain need?"** and adapts everything: darkness, message frequency, flow thresholds, energy greetings, pattern recognition, parallel capacity.

Every agent is implementing THAT model — making the system profile-aware and neurodivergent-native.
