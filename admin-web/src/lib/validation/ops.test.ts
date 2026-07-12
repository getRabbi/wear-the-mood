import { describe, expect, it } from "vitest";

import { flagToggleSchema, presetActiveSchema, presetUpdateSchema } from "./ops";

const uuid = "9f1c8e2a-1234-4abc-9def-000000000001";

describe("flagToggleSchema", () => {
  it("accepts a snake_case key + boolean string", () => {
    expect(flagToggleSchema.safeParse({ key: "feature_giveaway_chat", enabled: "true" }).success).toBe(true);
  });
  it("rejects a weird key", () => {
    expect(flagToggleSchema.safeParse({ key: "DROP TABLE;", enabled: "true" }).success).toBe(false);
  });
});

describe("presetUpdateSchema", () => {
  it("accepts name + https url + sort order", () => {
    const parsed = presetUpdateSchema.safeParse({
      presetId: uuid,
      name: "Female Studio Mannequin",
      imageUrl: "https://cdn/x.jpg",
      sortOrder: "3",
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.sortOrder).toBe(3);
  });
  it("accepts an empty image url (clears it)", () => {
    expect(
      presetUpdateSchema.safeParse({ presetId: uuid, name: "X", imageUrl: "", sortOrder: "1" })
        .success
    ).toBe(true);
  });
  it("rejects a non-https image url", () => {
    expect(
      presetUpdateSchema.safeParse({
        presetId: uuid,
        name: "X",
        imageUrl: "http://insecure/x.jpg",
        sortOrder: "1",
      }).success
    ).toBe(false);
  });
  it("rejects a blank name", () => {
    expect(
      presetUpdateSchema.safeParse({ presetId: uuid, name: " ", imageUrl: "", sortOrder: "1" })
        .success
    ).toBe(false);
  });
});

describe("presetActiveSchema", () => {
  it("accepts uuid + boolean string", () => {
    expect(presetActiveSchema.safeParse({ presetId: uuid, active: "false" }).success).toBe(true);
    expect(presetActiveSchema.safeParse({ presetId: "x", active: "true" }).success).toBe(false);
  });
});
