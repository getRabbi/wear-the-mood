import { z } from "zod";

export const creditAdjustSchema = z.object({
  userId: z.string().uuid(),
  amount: z.coerce
    .number()
    .int("Whole numbers only.")
    .refine((n) => n !== 0, "Amount can't be zero.")
    .refine((n) => Math.abs(n) <= 100000, "Amount too large."),
  reason: z.string().trim().min(1, "A reason is required.").max(500),
});

export const SEGMENTS = [
  "all",
  "free_users",
  "premium_users",
  "inactive_7d",
  "inactive_30d",
  "seed_excluded",
  "test_users",
] as const;

export const campaignSchema = z.object({
  title: z.string().trim().min(1, "Title is required.").max(120),
  body: z.string().trim().min(1, "Body is required.").max(500),
  segment: z.enum(SEGMENTS),
});

export const campaignIdSchema = z.object({
  campaignId: z.coerce.number().int().positive("Bad campaign id."),
});
