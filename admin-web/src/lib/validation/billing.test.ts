import { describe, expect, it } from "vitest";

import { campaignSchema, creditAdjustSchema } from "@/lib/validation/billing";

const UUID = "11111111-1111-1111-1111-111111111111";

describe("billing schemas", () => {
  it("credit adjust: non-zero integer + reason + uuid", () => {
    expect(creditAdjustSchema.safeParse({ userId: UUID, amount: "5", reason: "comp" }).success).toBe(
      true
    );
    expect(creditAdjustSchema.safeParse({ userId: UUID, amount: "-3", reason: "fix" }).success).toBe(
      true
    );
    expect(creditAdjustSchema.safeParse({ userId: UUID, amount: "0", reason: "x" }).success).toBe(
      false
    );
    expect(creditAdjustSchema.safeParse({ userId: UUID, amount: "5", reason: "" }).success).toBe(
      false
    );
  });

  it("campaign: title/body/segment required + valid segment", () => {
    expect(campaignSchema.safeParse({ title: "Hi", body: "There", segment: "all" }).success).toBe(
      true
    );
    expect(
      campaignSchema.safeParse({ title: "Hi", body: "There", segment: "nope" }).success
    ).toBe(false);
    expect(campaignSchema.safeParse({ title: "", body: "There", segment: "all" }).success).toBe(
      false
    );
  });
});
