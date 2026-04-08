const CommandPaletteHook = {
  mounted() {
    this._lastFocusedIndex = 0;
    this._currentIndex = 0;
    this._flowGuardActive = false;
    this._flowGuardEl = null;

    this.handleKeyDown = (e) => {
      // Cmd+K or Ctrl+K — with flow guard
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();

        // Context switch guard: if in flow, show warning first
        const flowIndicator = document.querySelector("[data-flow-state]");
        const inFlow =
          flowIndicator && flowIndicator.dataset.flowState === "flowing";

        if (inFlow && !this._flowGuardActive) {
          this._showFlowGuard();
          return;
        }

        this._flowGuardActive = false;
        this.pushEvent("toggle_command_palette", {});
      }

      // Escape to close (also dismisses flow guard)
      if (e.key === "Escape") {
        if (this._flowGuardActive) {
          this._dismissFlowGuard();
          return;
        }
        this.pushEvent("close_command_palette", {});
      }

      // Cmd+T for new terminal
      if ((e.metaKey || e.ctrlKey) && e.key === "t") {
        e.preventDefault();
        this.pushEvent("new_session", {});
      }

      // Cmd+W to kill focused terminal
      if ((e.metaKey || e.ctrlKey) && e.key === "w") {
        e.preventDefault();
        this.pushEvent("kill_focused", {});
      }

      // Cmd+Shift+I for stats/evidence panel
      if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === "I") {
        e.preventDefault();
        this.pushEvent("toggle_stats", {});
      }

      // Cmd+1-9 or Alt+1-9 to focus terminal by index
      if (
        ((e.metaKey || e.ctrlKey) && e.key >= "1" && e.key <= "9") ||
        (e.altKey && !e.metaKey && !e.ctrlKey && e.key >= "1" && e.key <= "9")
      ) {
        e.preventDefault();
        const idx = parseInt(e.key) - 1;
        this._lastFocusedIndex = this._currentIndex;
        this._currentIndex = idx;
        this.pushEvent("focus_by_index", { index: idx });
      }

      // Cmd+0 or Escape to return to grid
      if ((e.metaKey || e.ctrlKey) && e.key === "0") {
        e.preventDefault();
        this.pushEvent("unfocus", {});
      }

      // Alt+Left: previous terminal
      if (e.altKey && !e.metaKey && !e.ctrlKey && e.key === "ArrowLeft") {
        e.preventDefault();
        this.pushEvent("focus_prev", {});
      }

      // Alt+Right: next terminal
      if (e.altKey && !e.metaKey && !e.ctrlKey && e.key === "ArrowRight") {
        e.preventDefault();
        this.pushEvent("focus_next", {});
      }

      // Ctrl+Tab: switch to last focused terminal
      if (e.ctrlKey && e.key === "Tab") {
        e.preventDefault();
        this.pushEvent("focus_by_index", { index: this._lastFocusedIndex });
        // Swap current and last
        const tmp = this._currentIndex;
        this._currentIndex = this._lastFocusedIndex;
        this._lastFocusedIndex = tmp;
      }

      // Cmd+Shift+B for burst mode (opens palette pre-filtered)
      if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === "B") {
        e.preventDefault();
        this.pushEvent("toggle_command_palette", {});
        // Small delay to let palette open, then we could type "burst"
        // For now just opens the palette — user picks project and clicks BURST
      }

      // Cmd+Shift+S to save current workspace
      if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === "S") {
        e.preventDefault();
        const name = prompt("Workspace name:");
        if (name && name.trim()) {
          this.pushEvent("save_workspace", { name: name.trim() });
        }
      }
    };

    document.addEventListener("keydown", this.handleKeyDown);
  },

  _showFlowGuard() {
    this._flowGuardActive = true;

    // Create the guard overlay
    const guard = document.createElement("div");
    guard.id = "flow-guard";
    guard.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      z-index: 60;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 12px;
      background: rgba(255, 208, 74, 0.08);
      border-bottom: 1px solid rgba(255, 208, 74, 0.2);
      animation: slide-in 0.15s ease-out;
    `;

    guard.innerHTML = `
      <span style="color: #ffd04a; font-size: 12px; font-family: monospace; letter-spacing: 0.05em;">
        You're in flow — context switch anyway?
      </span>
      <span style="color: #5a5a5a; font-size: 10px; font-family: monospace; margin-left: 12px;">
        Cmd+K again to proceed · Esc to stay
      </span>
    `;

    document.body.appendChild(guard);
    this._flowGuardEl = guard;

    // Auto-dismiss after 3 seconds if no action
    this._flowGuardTimeout = setTimeout(() => {
      this._dismissFlowGuard();
    }, 3000);
  },

  _dismissFlowGuard() {
    this._flowGuardActive = false;
    clearTimeout(this._flowGuardTimeout);
    if (this._flowGuardEl) {
      this._flowGuardEl.remove();
      this._flowGuardEl = null;
    }
  },

  destroyed() {
    this._dismissFlowGuard();
    document.removeEventListener("keydown", this.handleKeyDown);
  },
};

export default CommandPaletteHook;
