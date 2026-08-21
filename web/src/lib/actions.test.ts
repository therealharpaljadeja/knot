import { describe, expect, it } from "vitest";
import { MAX_ACTIONS } from "./actions";

describe("action canvas limits", () => {
  it("allows three user actions", () => {
    expect(MAX_ACTIONS).toBe(3);
  });
});
