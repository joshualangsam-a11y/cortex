/**
 * AgentChat — auto-scroll for the message container.
 * AgentInput — textarea auto-resize + Enter to submit.
 */
const AgentChatHook = {
  mounted() {
    this.scrollToBottom();

    this.handleEvent("text-delta", () => {
      if (this.isNearBottom()) this.scrollToBottom();
    });

    this.observer = new MutationObserver(() => {
      if (this.isNearBottom()) this.scrollToBottom();
    });

    this.observer.observe(this.el, { childList: true, subtree: true });
  },

  destroyed() {
    this.observer?.disconnect();
  },

  isNearBottom() {
    return (
      this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 150
    );
  },

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight;
    });
  },
};

const AgentInputHook = {
  mounted() {
    this.el.addEventListener("input", () => this.resize());
    this.el.addEventListener("keydown", (e) => this.handleKey(e));
    this.resize();
  },

  updated() {
    // Reset height when input is cleared (after submit)
    if (this.el.value === "" || this.el.textContent === "") {
      this.el.style.height = "auto";
    }
  },

  resize() {
    this.el.style.height = "auto";
    this.el.style.height = Math.min(this.el.scrollHeight, 200) + "px";
  },

  handleKey(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      // Only submit if there's content
      const value = this.el.value?.trim() || this.el.textContent?.trim();
      if (value) {
        const form = this.el.closest("form");
        if (form) {
          form.dispatchEvent(
            new Event("submit", { bubbles: true, cancelable: true })
          );
        }
      }
    }
  },
};

export default AgentChatHook;
export { AgentInputHook };
