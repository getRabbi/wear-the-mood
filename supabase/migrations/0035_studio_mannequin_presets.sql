-- ============================================================================
-- 0035 — Rename studio try-on presets to "Studio Mannequin" (provider strategy)
--
-- The Try-On Body System uses photorealistic fashion MANNEQUIN presets (realistic
-- human proportions, minimal/no face, neutral base outfit, try-on-friendly pose)
-- rather than "real human model" presets. This renames the 5 studio_tryon rows
-- (seeded inactive in 0033) to their mannequin names. Style keys are unchanged so
-- the app/backend keep working. Rows stay INACTIVE with NULL image_url — they only
-- go live after real R2/CDN mannequin images are uploaded, QA'd (2D + AI try-on)
-- and manually activated (never activate a null/broken image_url).
--
-- Additive, idempotent, re-runnable. Apply to DEV first; prod on the next deploy.
-- ============================================================================

update public.tryon_model_presets set name = 'Female Studio Mannequin'
  where kind = 'studio_tryon' and style = 'female_studio';
update public.tryon_model_presets set name = 'Modest Studio Mannequin'
  where kind = 'studio_tryon' and style = 'modest';
update public.tryon_model_presets set name = 'Male Studio Mannequin'
  where kind = 'studio_tryon' and style = 'male_studio';
update public.tryon_model_presets set name = 'Curve Studio Mannequin'
  where kind = 'studio_tryon' and style = 'curve';
update public.tryon_model_presets set name = 'Neutral Studio Mannequin'
  where kind = 'studio_tryon' and style = 'neutral';

-- Safety net: never let a preset be active without a real image (defends against
-- a bad manual activation). Idempotent.
update public.tryon_model_presets
   set is_active = false
 where is_active = true and (image_url is null or length(trim(image_url)) = 0);

-- ============================================================================
-- End of 0035
-- ============================================================================
