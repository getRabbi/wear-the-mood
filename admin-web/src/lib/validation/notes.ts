import { z } from "zod";

// Allowed admin-note targets — mirrors the admin_notes CHECK constraint (0024).
export const NOTE_TARGET_TYPES = [
  "user",
  "post",
  "comment",
  "report",
  "appeal",
  "subscription",
  "credit_adjustment",
] as const;

export const addNoteSchema = z.object({
  targetType: z.enum(NOTE_TARGET_TYPES),
  targetId: z.string().min(1).max(200),
  note: z.string().trim().min(1, "Note can't be empty.").max(2000, "Note is too long."),
});

export type AddNoteInput = z.infer<typeof addNoteSchema>;
