import { z } from "zod";

const reason = z.string().trim().min(1, "A reason is required.").max(500, "Too long.");

export const generatedImageActionSchema = z.object({
  imageId: z.string().uuid(),
  reason,
});

// Remove-from-report chains admin_remove_generated_image + admin_set_report_status.
export const generatedImageFromReportSchema = z.object({
  reportId: z.string().uuid(),
  imageId: z.string().uuid(),
  reason,
});
