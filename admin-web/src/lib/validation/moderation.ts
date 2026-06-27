import { z } from "zod";

const reason = z.string().trim().min(1, "A reason is required.").max(500, "Reason is too long.");

export const userActionSchema = z.object({
  userId: z.string().uuid(),
  reason,
});

export const postActionSchema = z.object({
  postId: z.string().uuid(),
  reason,
});

export const commentActionSchema = z.object({
  commentId: z.string().uuid(),
  reason,
});

export type UserActionInput = z.infer<typeof userActionSchema>;
export type PostActionInput = z.infer<typeof postActionSchema>;
export type CommentActionInput = z.infer<typeof commentActionSchema>;
