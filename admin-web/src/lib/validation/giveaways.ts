import { z } from "zod";

const reason = z.string().trim().min(1, "A reason is required.").max(500, "Too long.");

export const giveawayActionSchema = z.object({
  giveawayId: z.string().uuid(),
  reason,
});

// Hide-from-report chains admin_hide_giveaway + admin_set_report_status.
export const giveawayFromReportSchema = z.object({
  reportId: z.string().uuid(),
  giveawayId: z.string().uuid(),
  reason,
});

// Review a reported pickup chat: 'clear' drops report_flag (the retention cron
// then redacts on its normal pass); 'keep_frozen' preserves the transcript.
// reportId is optional — when present, the linked report is resolved too.
export const chatReviewSchema = z.object({
  chatId: z.string().uuid(),
  decision: z.enum(["clear", "keep_frozen"]),
  reportId: z.string().uuid().optional().or(z.literal("").transform(() => undefined)),
  reason,
});
