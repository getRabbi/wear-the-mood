import { z } from "zod";

const reason = z.string().trim().min(1, "A reason / note is required.").max(500, "Too long.");

export const reportActionSchema = z.object({
  reportId: z.string().uuid(),
  reason,
});

export const hideTargetSchema = z.object({
  reportId: z.string().uuid(),
  subjectType: z.enum(["post", "comment"]),
  subjectId: z.string().uuid(),
  reason,
});

export const banFromReportSchema = z.object({
  reportId: z.string().uuid(),
  reportedUserId: z.string().uuid(),
  reason,
});

export const strikeFromReportSchema = z.object({
  reportId: z.string().uuid(),
  userId: z.string().uuid(),
  reason,
});

export const appealResolveSchema = z.object({
  appealId: z.string().regex(/^\d+$/, "Bad appeal id."),
  reason,
});
