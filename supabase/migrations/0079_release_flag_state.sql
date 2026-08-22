-- ============================================================================
-- 0079 — State the release's flag posture explicitly, instead of relying on
--        compiled defaults nobody can see from the database
--
-- WHY
-- ---
-- `flag_enabled(conn, key, default=...)` returns the CODE default when no row
-- exists. That is the right behaviour — a flag should only need a row when you
-- want to flip it — but it means "is strict category enforcement on in
-- production?" has, until now, been answerable only by reading Python and
-- knowing that no row exists. An absent row and a row set to the same value are
-- not the same fact: the first is an accident of history, the second is a
-- decision somebody made.
--
-- This release changes what two of these flags mean, so it states all of them:
--
--   wardrobe_require_metadata        ON  — a garment cannot be saved nameless
--                                          and uncategorised.
--   wardrobe_require_known_category  ON  — and the category must resolve to a
--                                          real body region. Previously OFF
--                                          only so the new client could be
--                                          verified against a permissive
--                                          server; the shipped picker cannot
--                                          emit an unreadable value, so this is
--                                          now the backstop rather than the
--                                          gate.
--   tryon_strict_categories          ON  — closes the legacy escape hatch that
--                                          let an unidentified garment fall
--                                          through to the provider's own
--                                          detector. Nothing shipped still
--                                          needs it: every current client sends
--                                          structured garments.
--
-- And it pins the two experiment flags OFF, because both can change what a user
-- is charged and neither has been reviewed for this release:
--
--   feature_credit_economics_v2      OFF — the tiered price ladder. Clamped to
--                                          one credit in code regardless, but a
--                                          price experiment should be turned on
--                                          deliberately, not inherited.
--   feature_render_gate_v2           OFF — lets a config row or an experiment
--                                          override the free lifetime
--                                          allowance. Off means the allowance
--                                          is exactly FREE_TRYON_TRIAL_CREDITS.
--
-- WHAT IT DOES NOT DO
-- -------------------
-- It does not touch `ai_tryon_enabled` or `ai_studio_enabled`. Those are
-- incident kill-switches, and a migration that re-enables a feature somebody
-- turned off during an outage is a migration that fights the operator. They
-- default ON in code; if a row exists saying otherwise, somebody meant it.
--
-- Idempotent, and reversible by setting any row back with a one-line update
-- from the admin console — that is the whole point of a flag.
-- ============================================================================

insert into public.feature_flags (key, enabled, description)
values
  ('wardrobe_require_metadata', true,
   'A manually created garment must carry a name and a category.'),
  ('wardrobe_require_known_category', true,
   'The category must resolve to a canonical try-on role. Backstop: the shipped '
   'picker cannot emit an unreadable value.'),
  ('tryon_strict_categories', true,
   'No provider-auto fallback for a garment whose role we could not resolve.'),
  ('feature_credit_economics_v2', false,
   'Tiered render pricing. OFF: every render is one app credit.'),
  ('feature_render_gate_v2', false,
   'Config/experiment override of the free lifetime allowance. OFF: the '
   'allowance is FREE_TRYON_TRIAL_CREDITS.')
on conflict (key) do update
   set enabled = excluded.enabled,
       description = excluded.description;

-- ── the free allowance, said once ───────────────────────────────────────────
-- `free_render_lifetime_limit` is only consulted when `feature_render_gate_v2`
-- is ON, which the block above pins OFF. It is still set to the release's
-- number so the two can never disagree if that flag is ever flipped for an
-- experiment — a stale 1 sitting here would silently halve the allowance the
-- moment somebody turned the gate on to test something unrelated.
--
-- Guarded: a database that has not run 0076 has no such table, and this
-- migration must not fail there.
do $$
begin
  if to_regclass('public.monetization_config') is not null then
    insert into public.monetization_config (key, value)
    values ('free_render_lifetime_limit', '3'::jsonb)
    on conflict (key) do update set value = excluded.value;

    -- Prices are compiled and clamped; an override row here can only ever lower
    -- one, never raise it (core.monetization._capped). Clearing them means the
    -- code is the single source of truth for what a render costs.
    --
    -- `'null'::jsonb`, NOT a SQL NULL. `_coerce` treats both as "use the code
    -- default", but the column is NOT NULL in production, so writing a SQL null
    -- aborts the migration — which is exactly what it did on the first attempt.
    -- The seeded state (0076) is already jsonb null, so on a healthy database
    -- this is a no-op that says so out loud.
    update public.monetization_config
       set value = 'null'::jsonb
     where key in ('render_cost_standard', 'render_cost_hd', 'render_cost_enhance')
       and value is distinct from 'null'::jsonb;
  end if;
end $$;
