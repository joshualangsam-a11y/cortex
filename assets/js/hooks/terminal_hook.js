import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { SearchAddon } from "@xterm/addon-search";
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

    // Search addon
    this.searchAddon = new SearchAddon();
    this.term.loadAddon(this.searchAddon);

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

    // Search bar UI
    this._searchVisible = false;
    this._createSearchBar();

    // Copy mode: Ctrl+Shift+C copies selection
    this._handleTermKeydown = (e) => {
      // Ctrl+Shift+F: toggle search
      if (e.ctrlKey && e.shiftKey && e.key === "F") {
        e.preventDefault();
        e.stopPropagation();
        this._toggleSearch();
        return;
      }

      // Ctrl+Shift+C: copy selection
      if (e.ctrlKey && e.shiftKey && e.key === "C") {
        const selection = this.term.getSelection();
        if (selection) {
          e.preventDefault();
          e.stopPropagation();
          navigator.clipboard.writeText(selection).then(() => {
            this._showCopiedFlash();
          });
        }
      }
    };

    // Attach to the terminal's DOM element so it captures before xterm
    this.el.addEventListener("keydown", this._handleTermKeydown, true);
  },

  _createSearchBar() {
    const bar = document.createElement("div");
    bar.className = "cortex-search-bar";
    bar.style.cssText = `
      display: none;
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      z-index: 10;
      background: #0a0a0a;
      border-bottom: 1px solid #1a1a1a;
      padding: 4px 8px;
      display: none;
      align-items: center;
      gap: 6px;
    `;

    const input = document.createElement("input");
    input.type = "text";
    input.placeholder = "Search...";
    input.style.cssText = `
      flex: 1;
      background: #050505;
      border: 1px solid #1a1a1a;
      border-radius: 4px;
      color: #e8dcc0;
      font-size: 12px;
      font-family: 'SF Mono', 'Fira Code', monospace;
      padding: 3px 8px;
      outline: none;
    `;

    const prevBtn = document.createElement("button");
    prevBtn.textContent = "\u2191";
    prevBtn.title = "Previous (Shift+Enter)";
    prevBtn.style.cssText = this._searchBtnStyle();

    const nextBtn = document.createElement("button");
    nextBtn.textContent = "\u2193";
    nextBtn.title = "Next (Enter)";
    nextBtn.style.cssText = this._searchBtnStyle();

    const closeBtn = document.createElement("button");
    closeBtn.textContent = "x";
    closeBtn.title = "Close (Escape)";
    closeBtn.style.cssText = this._searchBtnStyle();

    // Events
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && e.shiftKey) {
        e.preventDefault();
        this.searchAddon.findPrevious(input.value);
      } else if (e.key === "Enter") {
        e.preventDefault();
        this.searchAddon.findNext(input.value);
      } else if (e.key === "Escape") {
        e.preventDefault();
        this._hideSearch();
      }
    });

    input.addEventListener("input", () => {
      if (input.value) {
        this.searchAddon.findNext(input.value);
      }
    });

    prevBtn.addEventListener("click", () => {
      if (input.value) this.searchAddon.findPrevious(input.value);
    });

    nextBtn.addEventListener("click", () => {
      if (input.value) this.searchAddon.findNext(input.value);
    });

    closeBtn.addEventListener("click", () => {
      this._hideSearch();
    });

    bar.appendChild(input);
    bar.appendChild(prevBtn);
    bar.appendChild(nextBtn);
    bar.appendChild(closeBtn);

    this._searchBar = bar;
    this._searchInput = input;
    this.el.appendChild(bar);
  },

  _searchBtnStyle() {
    return `
      background: #0a0a0a;
      border: 1px solid #1a1a1a;
      border-radius: 4px;
      color: #e8dcc0;
      font-size: 11px;
      padding: 2px 8px;
      cursor: pointer;
      font-family: monospace;
      line-height: 1.4;
    `;
  },

  _toggleSearch() {
    if (this._searchVisible) {
      this._hideSearch();
    } else {
      this._showSearch();
    }
  },

  _showSearch() {
    this._searchVisible = true;
    this._searchBar.style.display = "flex";
    this._searchInput.focus();
    this._searchInput.select();
  },

  _hideSearch() {
    this._searchVisible = false;
    this._searchBar.style.display = "none";
    this._searchInput.value = "";
    this.searchAddon.clearDecorations();
    this.term.focus();
  },

  _showCopiedFlash() {
    // Remove any existing flash
    const existing = this.el.querySelector(".cortex-copied-flash");
    if (existing) existing.remove();

    const flash = document.createElement("div");
    flash.className = "cortex-copied-flash";
    flash.textContent = "copied!";
    flash.style.cssText = `
      position: absolute;
      top: 8px;
      right: 8px;
      z-index: 10;
      background: #0a0a0a;
      border: 1px solid #ffd04a;
      border-radius: 5px;
      color: #ffd04a;
      font-size: 11px;
      font-family: monospace;
      padding: 3px 10px;
      pointer-events: none;
      animation: cortex-flash-fade 1.2s ease-out forwards;
    `;

    this.el.appendChild(flash);
    setTimeout(() => flash.remove(), 1300);
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
    this.el.removeEventListener("keydown", this._handleTermKeydown, true);
    this.resizeObserver?.disconnect();
    this.webglAddon?.dispose();
    this.searchAddon?.dispose();
    this.term?.dispose();
  },
};

export default TerminalHook;
