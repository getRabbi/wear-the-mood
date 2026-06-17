-- ============================================================================
-- 0014 — Multi-garment AI try-on (CLAUDE.md §7)
--
-- The Try-On Studio lets users stack multiple garments. AI try-on now renders
-- the WHOLE stack (the worker chains the provider's single-garment calls). We
-- store the full ordered stack alongside the existing primary garment so old
-- single-garment clients keep working unchanged.
--
-- garment_image_urls: the full stack in RENDER order (dress/base → top → bottom
--   → outerwear → shoes/bag/accessory). NULL/empty for legacy single-garment
--   jobs, which still read garment_image_url.
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

alter table public.tryon_jobs
  add column if not exists garment_image_urls text[];
