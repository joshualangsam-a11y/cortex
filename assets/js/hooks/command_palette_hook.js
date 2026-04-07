const CommandPaletteHook = {
  mounted() {
    this._lastFocusedIndex = 0;
    this._currentIndex = 0;

    this.handleKeyDown = (e) => {
      // Cmd+K or Ctrl+K
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        this.pushEvent("toggle_command_palette", {});
      }

      // Escape to close
      if (e.key === "Escape") {
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

  destroyed() {
    document.removeEventListener("keydown", this.handleKeyDown);
  },
};

export default CommandPaletteHook;
