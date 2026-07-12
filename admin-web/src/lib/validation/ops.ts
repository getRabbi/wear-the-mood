import { z } from "zod";

export const flagToggleSchema = z.object({
  key: z
    .string()
    .trim()
    .min(1)
    .max(80)
    .regex(/^[a-z0-9_]+$/, "Bad flag key."),
  enabled: z.enum(["true", "false"]),
});

export const presetUpdateSchema = z.object({
  presetId: z.string().uuid(),
  name: z.string().trim().min(1, "A name is required.").max(80, "Too long."),
  // Existing hosted url; a fresh file upload (handled separately) overrides it.
  imageUrl: z
    .string()
    .trim()
    .max(500)
    .refine((v) => v === "" || v.startsWith("https://"), "Must be an https URL.")
    .optional()
    .or(z.literal("")),
  sortOrder: z.coerce.number().int().min(0).max(999),
});

export const presetActiveSchema = z.object({
  presetId: z.string().uuid(),
  active: z.enum(["true", "false"]),
});
