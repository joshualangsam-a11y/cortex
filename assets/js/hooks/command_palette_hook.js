const CommandPaletteHook = {
  mounted() {
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

      // Cmd+1-9 to focus terminal by index
      if ((e.metaKey || e.ctrlKey) && e.key >= "1" && e.key <= "9") {
        e.preventDefault();
        this.pushEvent("focus_by_index", { index: parseInt(e.key) - 1 });
      }

      // Cmd+0 or Escape to return to grid
      if ((e.metaKey || e.ctrlKey) && e.key === "0") {
        e.preventDefault();
        this.pushEvent("unfocus", {});
      }
    };

    document.addEventListener("keydown", this.handleKeyDown);
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeyDown);
  },
};

export default CommandPaletteHook;
