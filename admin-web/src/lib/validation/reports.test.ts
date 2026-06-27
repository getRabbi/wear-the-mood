import { describe, expect, it } from "vitest";

import {
  appealResolveSchema,
  banFromReportSchema,
  hideTargetSchema,
  reportActionSchema,
} from "@/lib/validation/reports";

const UUID = "11111111-1111-1111-1111-111111111111";

describe("report/appeal action schemas", () => {
  it("report action needs a uuid + reason", () => {
    expect(reportActionSchema.safeParse({ reportId: UUID, reason: "spam" }).success).toBe(true);
    expect(reportActionSchema.safeParse({ reportId: UUID, reason: "" }).success).toBe(false);
    expect(reportActionSchema.safeParse({ reportId: "x", reason: "spam" }).success).toBe(false);
  });

  it("hide target only accepts post/comment subject types", () => {
    expect(
      hideTargetSchema.safeParse({ reportId: UUID, subjectType: "post", subjectId: UUID, reason: "x" })
        .success
    ).toBe(true);
    expect(
      hideTargetSchema.safeParse({ reportId: UUID, subjectType: "user", subjectId: UUID, reason: "x" })
        .success
    ).toBe(false);
  });

  it("ban-from-report needs the reported user uuid", () => {
    expect(
      banFromReportSchema.safeParse({ reportId: UUID, reportedUserId: UUID, reason: "ban" }).success
    ).toBe(true);
    expect(
      banFromReportSchema.safeParse({ reportId: UUID, reportedUserId: "nope", reason: "ban" }).success
    ).toBe(false);
  });

  it("appeal id must be numeric", () => {
    expect(appealResolveSchema.safeParse({ appealId: "42", reason: "ok" }).success).toBe(true);
    expect(appealResolveSchema.safeParse({ appealId: "abc", reason: "ok" }).success).toBe(false);
  });
});
