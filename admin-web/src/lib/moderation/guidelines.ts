// Violation → default action / reason map (BUILD_PROMPT §20). Surfaced as preset
// reason chips in the moderation dialog so enforcement is consistent + every
// action carries a clear, policy-aligned reason. The mapping is advisory — the
// moderator still chooses the action; the DB requires a non-blank reason.

export type ViolationPreset = {
  label: string;
  reason: string;
  suggested: string; // human hint of the default action
};

export const VIOLATION_PRESETS: ViolationPreset[] = [
  { label: "Spam / scam", reason: "Spam or scam content.", suggested: "Hide; repeat → suspend" },
  {
    label: "Harassment / hate",
    reason: "Harassment or hateful content.",
    suggested: "Delete + suspend; severe → ban",
  },
  {
    label: "Nudity / sexual",
    reason: "Nudity or sexual content.",
    suggested: "Delete + shadowban pending review",
  },
  {
    label: "Minor safety",
    reason: "Content endangering a minor.",
    suggested: "Delete + ban if severe",
  },
  { label: "Copyright", reason: "Copyright violation.", suggested: "Hide pending review" },
  { label: "Off-topic / low quality", reason: "Off-topic or low-quality post.", suggested: "Hide" },
  {
    label: "Fake / impersonation",
    reason: "Fake account or impersonation.",
    suggested: "Suspend; repeat → ban",
  },
  { label: "Ban evasion", reason: "Ban evasion.", suggested: "Ban" },
  { label: "Self-harm", reason: "Self-harm content.", suggested: "Hide; escalate per policy" },
  { label: "Other", reason: "", suggested: "Moderator decides — give a reason" },
];
