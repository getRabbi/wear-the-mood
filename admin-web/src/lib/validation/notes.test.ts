import { describe, expect, it } from "vitest";

import { addNoteSchema } from "@/lib/validation/notes";

describe("addNoteSchema", () => {
  it("accepts a valid user note", () => {
    const r = addNoteSchema.safeParse({
      targetType: "user",
      targetId: "11111111-1111-1111-1111-111111111111",
      note: "Looks fine.",
    });
    expect(r.success).toBe(true);
  });

  it("rejects an empty / whitespace note", () => {
    expect(addNoteSchema.safeParse({ targetType: "user", targetId: "u1", note: "" }).success).toBe(
      false
    );
    expect(
      addNoteSchema.safeParse({ targetType: "user", targetId: "u1", note: "   " }).success
    ).toBe(false);
  });

  it("rejects an unknown target type", () => {
    expect(
      addNoteSchema.safeParse({ targetType: "spaceship", targetId: "u1", note: "hi" }).success
    ).toBe(false);
  });

  it("rejects an over-long note", () => {
    expect(
      addNoteSchema.safeParse({ targetType: "user", targetId: "u1", note: "x".repeat(2001) })
        .success
    ).toBe(false);
  });
});
