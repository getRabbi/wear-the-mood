-- ============================================================================
-- 0034 — Catalog Model Shot presets (BUILD_PROMPT_PRO_PROMAX.md Phase 4)
--
-- Seeds the 5 catalog model STYLES (studio / streetwear / modest / luxury /
-- cropped face) into tryon_model_presets (kind='catalog'), INACTIVE with a NULL
-- image_url. The catalog worker resolves an ACTIVE catalog preset by style and
-- renders the garment on it via the try-on provider; with no active preset it
-- fails cleanly and refunds (no fake output). The founder uploads real model
-- images, sets image_url and flips is_active=true to go live.
--
-- Additive, idempotent (guarded on style), re-runnable. Dev first, then prod.
-- ============================================================================

insert into public.tryon_model_presets
  (kind, name, style, body_type, skin_tone, pose_type, is_active, is_pro_only, sort_order)
select 'catalog', v.name, v.style, null, null, v.pose_type, false, true, v.sort_order
from (values
  ('Studio',      'studio',       'front_full', 1),
  ('Streetwear',  'streetwear',   'front_full', 2),
  ('Modest',      'modest',       'front_full', 3),
  ('Luxury',      'luxury',       'front_full', 4),
  ('Cropped face','cropped_face', 'cropped',    5)
) as v(name, style, pose_type, sort_order)
where not exists (
  select 1 from public.tryon_model_presets p
   where p.kind = 'catalog' and p.style = v.style
);

-- ============================================================================
-- End of 0034
-- ============================================================================
