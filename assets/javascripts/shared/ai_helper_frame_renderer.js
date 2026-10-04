// Prevent duplicate class declaration
if (typeof AiHelperFrameRenderer === "undefined") {
  /**
   * Coalesces render requests into at most one render per animation frame.
   * Streaming views re-render the whole accumulated response, so rendering
   * on every streamed token makes the total cost grow quadratically and
   * freezes the browser on long responses (see ADR-046). The render
   * callback reads the latest state itself when the frame runs.
   */
  window.AiHelperFrameRenderer = class {
    /**
     * @param {() => void} render - Called with no arguments to render the latest state.
     */
    constructor(render) {
      this.render = render;
      this.pendingFrame = null;
    }

    /**
     * Schedule a render on the next animation frame, unless one is already
     * pending.
     */
    schedule() {
      if (this.pendingFrame !== null) {
        return;
      }
      this.pendingFrame = requestAnimationFrame(() => {
        this.pendingFrame = null;
        this.render();
      });
    }

    /**
     * Run the pending render immediately, if any, so the latest state is
     * shown without waiting for the next frame.
     */
    flush() {
      if (this.pendingFrame !== null) {
        this.cancel();
        this.render();
      }
    }

    /**
     * Cancel the pending render, if any, so it cannot overwrite a final or
     * error state rendered afterwards.
     */
    cancel() {
      if (this.pendingFrame !== null) {
        cancelAnimationFrame(this.pendingFrame);
        this.pendingFrame = null;
      }
    }
  };
}
