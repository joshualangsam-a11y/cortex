const DragHook = {
  mounted() {
    this._draggedId = null;

    this.el.addEventListener("dragstart", (e) => {
      const container = e.target.closest("[data-drag-id]");
      if (!container) return;

      this._draggedId = container.dataset.dragId;
      container.style.opacity = "0.5";
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", this._draggedId);
    });

    this.el.addEventListener("dragend", (e) => {
      const container = e.target.closest("[data-drag-id]");
      if (container) container.style.opacity = "";
      this._draggedId = null;

      // Clean up all drop highlights
      this.el.querySelectorAll("[data-drag-id]").forEach((el) => {
        el.style.borderColor = "";
      });
    });

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";

      const container = e.target.closest("[data-drag-id]");
      if (container && container.dataset.dragId !== this._draggedId) {
        container.style.borderColor = "#ffd04a";
      }
    });

    this.el.addEventListener("dragleave", (e) => {
      const container = e.target.closest("[data-drag-id]");
      if (container) {
        container.style.borderColor = "";
      }
    });

    this.el.addEventListener("drop", (e) => {
      e.preventDefault();
      const targetContainer = e.target.closest("[data-drag-id]");
      if (!targetContainer) return;

      const targetId = targetContainer.dataset.dragId;
      targetContainer.style.borderColor = "";

      if (this._draggedId && this._draggedId !== targetId) {
        // Build new order from current DOM order, swapping dragged and target
        const containers = Array.from(
          this.el.querySelectorAll("[data-drag-id]")
        );
        const order = containers.map((el) => el.dataset.dragId);
        const fromIdx = order.indexOf(this._draggedId);
        const toIdx = order.indexOf(targetId);

        if (fromIdx !== -1 && toIdx !== -1) {
          // Remove from old position, insert at new
          order.splice(fromIdx, 1);
          order.splice(toIdx, 0, this._draggedId);
          this.pushEvent("reorder_sessions", { order: order });
        }
      }
    });
  },
};

export default DragHook;
