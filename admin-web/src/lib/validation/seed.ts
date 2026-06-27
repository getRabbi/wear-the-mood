import { z } from "zod";

export const SEED_TYPES = ["studio", "lookbook", "inspiration", "campaign"] as const;

export const createSeedAccountSchema = z.object({
  displayName: z.string().trim().min(1, "Display name is required.").max(80),
  username: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9_]{3,30}$/, "Username: 3-30 chars, a-z 0-9 _ only."),
  bio: z.string().trim().max(300).optional().or(z.literal("")),
  seedType: z.enum(SEED_TYPES),
  publicLabel: z.string().trim().min(1).max(40),
});

export const createSeedPostSchema = z.object({
  seedUserId: z.string().uuid(),
  caption: z.string().trim().max(2000).optional().or(z.literal("")),
  // Optional: the look image can come from an UPLOAD or this URL (one is required,
  // enforced in the action).
  imageUrl: z.string().url("Enter a valid image URL.").max(2000).optional().or(z.literal("")),
  tags: z.string().trim().max(300).optional().or(z.literal("")),
});

export const seedStatusSchema = z.object({
  seedId: z.string().regex(/^\d+$/),
  status: z.enum(["active", "paused", "archived"]),
});

export const updateSeedProfileSchema = z.object({
  userId: z.string().uuid(),
  displayName: z.string().trim().min(1, "Display name is required.").max(80),
  username: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9_]{3,30}$/, "Username: 3-30 chars, a-z 0-9 _ only."),
  bio: z.string().trim().max(300).optional().or(z.literal("")),
  publicLabel: z.string().trim().min(1).max(40),
  styleTags: z.string().trim().max(300).optional().or(z.literal("")),
});

export const seedCommentSchema = z.object({
  seedUserId: z.string().uuid(),
  postId: z.string().uuid(),
  body: z.string().trim().min(1, "Comment can't be empty.").max(500),
});

export const featurePostSchema = z.object({
  postId: z.string().uuid(),
  featured: z.enum(["true", "false"]),
});

export type CreateSeedAccountInput = z.infer<typeof createSeedAccountSchema>;
export type CreateSeedPostInput = z.infer<typeof createSeedPostSchema>;
