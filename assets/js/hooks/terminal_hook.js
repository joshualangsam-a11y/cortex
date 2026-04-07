import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { theme } from "../terminal/theme";

const TerminalHook = {
  mounted() {
    const sessionId = this.el.dataset.sessionId;
    this.sessionId = sessionId;
    this._destroyed = false;

    this.term = new Terminal({
      theme: theme,
      fontFamily:
        "'MartianMono Nerd Font', 'SF Mono', 'Fira Code', 'Cascadia Code', monospace",
      fontSize: 12,
      lineHeight: 1.2,
      cursorBlink: true,
      cursorStyle: "block",
      scrollback: 10000,
      allowProposedApi: true,
      convertEol: true,
    });

    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);
    this.term.open(this.el);

    try {
      this.webglAddon = new WebglAddon();
      this.term.loadAddon(this.webglAddon);
      this.webglAddon.onContextLoss(() => {
        this.webglAddon.dispose();
      });
    } catch (_e) {
      // Canvas fallback
    }

    // Fit after the DOM has had time to lay out the grid
    this._fitAndReport();
    // Extra fit passes to catch late layout
    setTimeout(() => this._fitAndReport(), 150);
    setTimeout(() => this._fitAndReport(), 500);

    // Input: keystrokes -> server
    this.term.onData((data) => {
      if (!this._destroyed) {
        this.pushEvent("terminal_input", {
          session_id: sessionId,
          data: btoa(data),
        });
      }
    });

    // Output: server -> xterm.js (binary safe)
    this.handleEvent(`terminal_output:${sessionId}`, ({ data }) => {
      const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
      this.term.write(bytes);
    });

    this.handleEvent(`terminal_scrollback:${sessionId}`, ({ data }) => {
      const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
      this.term.write(bytes);
    });

    // Resize observer with debounce
    this._resizeTimeout = null;
    this._lastCols = 0;
    this._lastRows = 0;

    this.resizeObserver = new ResizeObserver(() => {
      clearTimeout(this._resizeTimeout);
      this._resizeTimeout = setTimeout(() => this._fitAndReport(), 50);
    });

    this.resizeObserver.observe(this.el);

    // Also observe the parent container for focus/unfocus size changes
    const container = this.el.closest("[id^='terminal-container-']");
    if (container) {
      this._container = container;
      this.resizeObserver.observe(container);
    }
  },

  _fitAndReport() {
    if (this._destroyed) return;
    if (this.el.offsetWidth < 10 || this.el.offsetHeight < 10) return;

    try {
      this.fitAddon.fit();
    } catch (_e) {
      return;
    }

    const cols = this.term.cols;
    const rows = this.term.rows;

    // Only send resize if dimensions actually changed
    if (cols !== this._lastCols || rows !== this._lastRows) {
      this._lastCols = cols;
      this._lastRows = rows;
      this.pushEvent("resize", {
        session_id: this.sessionId,
        cols: cols,
        rows: rows,
      });
    }
  },

  updated() {
    // LiveView DOM update (focus/unfocus toggle)
    // Multiple fit passes to handle CSS transition reflow
    this._fitAndReport();
    setTimeout(() => this._fitAndReport(), 100);
    setTimeout(() => this._fitAndReport(), 300);
  },

  destroyed() {
    this._destroyed = true;
    clearTimeout(this._resizeTimeout);
    this.resizeObserver?.disconnect();
    this.webglAddon?.dispose();
    this.term?.dispose();
  },
};

export default TerminalHook;
