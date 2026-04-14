/**
 * AgentChat hook — handles auto-scroll and streaming text for the agent chat UI.
 */
const AgentChatHook = {
  mounted() {
    this.scrollToBottom();

    // Auto-scroll on new content
    this.handleEvent("text-delta", (_payload) => {
      this.scrollToBottom();
    });

    // Submit form on Enter (handled via phx-keydown, but also trigger from push_event)
    this.handleEvent("submit-form", () => {
      const form = this.el.closest("#agent-root")?.querySelector("form");
      if (form) {
        form.dispatchEvent(
          new Event("submit", { bubbles: true, cancelable: true })
        );
      }
    });

    // Observe DOM changes for auto-scroll (new messages added by LiveView)
    this.observer = new MutationObserver(() => {
      if (this.isNearBottom()) {
        this.scrollToBottom();
      }
    });

    this.observer.observe(this.el, { childList: true, subtree: true });
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },

  isNearBottom() {
    const threshold = 150;
    return (
      this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight <
      threshold
    );
  },

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight;
    });
  },
};

export default AgentChatHook;
