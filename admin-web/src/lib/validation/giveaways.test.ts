import { describe, expect, it } from "vitest";

import {
  chatReviewSchema,
  giveawayActionSchema,
  giveawayFromReportSchema,
} from "./giveaways";

const uuid = "9f1c8e2a-1234-4abc-9def-000000000001";
const uuid2 = "9f1c8e2a-1234-4abc-9def-000000000002";

describe("giveawayActionSchema", () => {
  it("accepts a uuid + reason", () => {
    expect(giveawayActionSchema.safeParse({ giveawayId: uuid, reason: "spam" }).success).toBe(
      true
    );
  });
  it("rejects a blank reason", () => {
    expect(giveawayActionSchema.safeParse({ giveawayId: uuid, reason: "  " }).success).toBe(
      false
    );
  });
  it("rejects a non-uuid id", () => {
    expect(giveawayActionSchema.safeParse({ giveawayId: "nope", reason: "x" }).success).toBe(
      false
    );
  });
});

describe("giveawayFromReportSchema", () => {
  it("requires both uuids", () => {
    expect(
      giveawayFromReportSchema.safeParse({ reportId: uuid, giveawayId: uuid2, reason: "x" })
        .success
    ).toBe(true);
    expect(
      giveawayFromReportSchema.safeParse({ reportId: "bad", giveawayId: uuid2, reason: "x" })
        .success
    ).toBe(false);
  });
});

describe("chatReviewSchema", () => {
  it("accepts clear and keep_frozen", () => {
    for (const decision of ["clear", "keep_frozen"]) {
      expect(
        chatReviewSchema.safeParse({ chatId: uuid, decision, reason: "reviewed" }).success
      ).toBe(true);
    }
  });
  it("rejects an unknown decision", () => {
    expect(
      chatReviewSchema.safeParse({ chatId: uuid, decision: "redact", reason: "x" }).success
    ).toBe(false);
  });
  it("treats an empty reportId as absent", () => {
    const parsed = chatReviewSchema.safeParse({
      chatId: uuid,
      decision: "clear",
      reportId: "",
      reason: "x",
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.reportId).toBeUndefined();
  });
  it("keeps a real reportId", () => {
    const parsed = chatReviewSchema.safeParse({
      chatId: uuid,
      decision: "keep_frozen",
      reportId: uuid2,
      reason: "x",
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.reportId).toBe(uuid2);
  });
});
