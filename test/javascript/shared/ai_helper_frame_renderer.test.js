import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { stubAnimationFrames } from "../support/animation_frames.js";
import { loadScript } from "../support/load_script.js";

describe("AiHelperFrameRenderer", () => {
  let frames;

  beforeEach(async () => {
    delete window.AiHelperFrameRenderer;
    await loadScript("assets/javascripts/shared/ai_helper_frame_renderer");
    frames = stubAnimationFrames();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("renders once per frame no matter how often it is scheduled", () => {
    const render = vi.fn();
    const renderer = new window.AiHelperFrameRenderer(render);

    renderer.schedule();
    renderer.schedule();
    renderer.schedule();

    expect(render).not.toHaveBeenCalled();
    expect(frames.pendingCount()).toBe(1);

    frames.flush();
    expect(render).toHaveBeenCalledTimes(1);

    renderer.schedule();
    frames.flush();
    expect(render).toHaveBeenCalledTimes(2);
  });

  it("cancel drops the pending render", () => {
    const render = vi.fn();
    const renderer = new window.AiHelperFrameRenderer(render);

    renderer.schedule();
    renderer.cancel();
    frames.flush();

    expect(render).not.toHaveBeenCalled();
    expect(frames.pendingCount()).toBe(0);
  });

  it("cancel is a no-op without a pending render", () => {
    const renderer = new window.AiHelperFrameRenderer(vi.fn());

    expect(() => renderer.cancel()).not.toThrow();
  });

  it("flush runs the pending render immediately and only once", () => {
    const render = vi.fn();
    const renderer = new window.AiHelperFrameRenderer(render);

    renderer.schedule();
    renderer.flush();

    expect(render).toHaveBeenCalledTimes(1);
    expect(frames.pendingCount()).toBe(0);

    frames.flush();
    expect(render).toHaveBeenCalledTimes(1);
  });

  it("flush does not render when nothing is pending", () => {
    const render = vi.fn();
    const renderer = new window.AiHelperFrameRenderer(render);

    renderer.flush();

    expect(render).not.toHaveBeenCalled();
  });

  it("can schedule again from inside a render", () => {
    const renderer = new window.AiHelperFrameRenderer(() => renderer.schedule());

    renderer.schedule();
    frames.flush();

    expect(frames.pendingCount()).toBe(1);
  });
});
