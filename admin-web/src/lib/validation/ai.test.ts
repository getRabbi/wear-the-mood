import { describe, expect, it } from "vitest";

import { generatedImageActionSchema, generatedImageFromReportSchema } from "./ai";

const uuid = "9f1c8e2a-1234-4abc-9def-000000000001";
const uuid2 = "9f1c8e2a-1234-4abc-9def-000000000002";

describe("generatedImageActionSchema", () => {
  it("accepts a uuid + reason", () => {
    expect(
      generatedImageActionSchema.safeParse({ imageId: uuid, reason: "nudity" }).success
    ).toBe(true);
  });
  it("rejects a blank reason", () => {
    expect(generatedImageActionSchema.safeParse({ imageId: uuid, reason: " " }).success).toBe(
      false
    );
  });
  it("rejects a non-uuid id", () => {
    expect(generatedImageActionSchema.safeParse({ imageId: "x", reason: "r" }).success).toBe(
      false
    );
  });
});

describe("generatedImageFromReportSchema", () => {
  it("requires both uuids + reason", () => {
    expect(
      generatedImageFromReportSchema.safeParse({ reportId: uuid, imageId: uuid2, reason: "r" })
        .success
    ).toBe(true);
    expect(
      generatedImageFromReportSchema.safeParse({ reportId: "bad", imageId: uuid2, reason: "r" })
        .success
    ).toBe(false);
  });
});
