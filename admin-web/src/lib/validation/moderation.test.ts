import { describe, expect, it } from "vitest";

import {
  commentActionSchema,
  postActionSchema,
  userActionSchema,
} from "@/lib/validation/moderation";

const UUID = "11111111-1111-1111-1111-111111111111";

describe("moderation action schemas", () => {
  it("require a non-empty reason", () => {
    expect(userActionSchema.safeParse({ userId: UUID, reason: "" }).success).toBe(false);
    expect(userActionSchema.safeParse({ userId: UUID, reason: "   " }).success).toBe(false);
    expect(userActionSchema.safeParse({ userId: UUID, reason: "spam" }).success).toBe(true);
  });

  it("reject a non-uuid target", () => {
    expect(userActionSchema.safeParse({ userId: "nope", reason: "x" }).success).toBe(false);
    expect(postActionSchema.safeParse({ postId: "nope", reason: "x" }).success).toBe(false);
    expect(commentActionSchema.safeParse({ commentId: "nope", reason: "x" }).success).toBe(false);
  });

  it("accept valid post/comment actions", () => {
    expect(postActionSchema.safeParse({ postId: UUID, reason: "nudity" }).success).toBe(true);
    expect(commentActionSchema.safeParse({ commentId: UUID, reason: "abuse" }).success).toBe(true);
  });
});
