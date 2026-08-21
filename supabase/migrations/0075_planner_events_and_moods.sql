-- ============================================================================
-- 0075 — Mood Planner v2 + Event Planner: the low-cost reasons to come back
--
-- ADDITIVE + IDEMPOTENT. Two new user-owned tables, RLS-scoped to their owner.
-- No existing object is touched. Both features ship behind their own flag, OFF
-- by default, so deploying this changes nothing a user can see.
--
-- WHY
-- ---
-- Every current reason to open WTM costs a FASHN render. That is a product
-- problem before it is an economics one: a user with no credits has no reason
-- to open the app at all, and a user with credits burns them on browsing.
--
-- Both tables here exist to make the app worth opening WITHOUT generating an
-- image. A mood plan is styling direction, computed from the user's own
-- wardrobe and their Style Memory — no provider call, no credit, no charge.
-- Rendering stays an explicit, separate, paid act the user asks for by name
-- ("See it on me").
--
-- The Event Planner deliberately stores what the user TYPED. No calendar
-- permission is requested, no calendar is read, and no calendar is written
-- (§15) — that integration is a separate, permission-aware project.
--
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ── mood_plans ───────────────────────────────────────────────────────────────
-- One row per "how do you want to feel today?" answer. Small and disposable by
-- design: the plan itself is deterministic, so this table exists to remember
-- that the user made one (Home's "Continue your style") rather than to be the
-- only copy of the styling advice.
create table if not exists public.mood_plans (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  -- The mood key ('calm' | 'confident' | 'bold' | 'rebel'), matching the app's
  -- existing four-zone mood board. Text, not an enum: the board's vocabulary is
  -- a product decision that has changed before and will again.
  mood       text not null,
  -- Optional context ('everyday' | 'work' | 'date' | 'brunch' | 'wedding' |
  -- 'night_out'). Null is a valid answer — the user just picked a feeling.
  occasion   text,
  -- The rendered direction: the headline, the guidance lines and the wardrobe
  -- item ids it referenced. Stored so re-opening shows the SAME plan rather
  -- than silently re-rolling it under the user.
  direction  jsonb not null default '{}'::jsonb,
  -- RESERVED, and currently never written. It is where "this plan became a
  -- paid render" would be recorded, which is the one number that would show
  -- whether free planning feeds the paid loop. Wiring it means threading a plan
  -- id through the try-on submit path — the highest-risk path in the app — and
  -- that was not worth doing for a metric in the same change that introduced
  -- the planner. Left declared so the column exists when it is.
  rendered_job_id uuid,
  created_at timestamptz not null default now()
);

comment on table public.mood_plans is
  'A low-cost styling direction for a chosen mood/occasion. Never consumes a '
  'provider render; rendering is a separate explicit action (§14).';

create index if not exists mood_plans_user_created_idx
  on public.mood_plans (user_id, created_at desc);

alter table public.mood_plans enable row level security;

drop policy if exists mood_plans_select_own on public.mood_plans;
create policy mood_plans_select_own on public.mood_plans
  for select using (auth.uid() = user_id);

drop policy if exists mood_plans_insert_own on public.mood_plans;
create policy mood_plans_insert_own on public.mood_plans
  for insert with check (auth.uid() = user_id);

drop policy if exists mood_plans_update_own on public.mood_plans;
create policy mood_plans_update_own on public.mood_plans
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists mood_plans_delete_own on public.mood_plans;
create policy mood_plans_delete_own on public.mood_plans
  for delete using (auth.uid() = user_id);

-- ── style_events ─────────────────────────────────────────────────────────────
-- "Wedding — 5 September, black satin look saved." Manually entered, entirely
-- user-owned, with no calendar coupling of any kind.
create table if not exists public.style_events (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  name          text not null check (length(trim(name)) between 1 and 120),
  -- Stored as an absolute instant. The app sends the user's local time
  -- converted to UTC; reminders are scheduled against the user's stored
  -- timezone exactly like the daily stylist push (§20).
  event_at      timestamptz not null,
  occasion      text,
  -- The saved look this event is dressed for. Saved looks live on the DEVICE
  -- (encrypted local collections), so this is the look's stable id plus the
  -- durable image URL that the save already produced — not a foreign key to a
  -- table that does not exist. Both nullable: an event with no look yet is the
  -- normal starting state.
  look_ref      text,
  look_image_url text,
  note          text check (note is null or length(note) <= 500),
  -- Reminders are strictly opt-in per event (§23). Default FALSE: creating an
  -- event must never sign the user up for push.
  reminder_opt_in boolean not null default false,
  -- Which reminders have already gone out, so a re-run of the cron cannot send
  -- the 7-day nudge twice. Values: 'd7' | 'd2' | 'd0'.
  reminders_sent  text[] not null default '{}'::text[],
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.style_events is
  'User-entered events (name, date, occasion, optional saved look). No calendar '
  'permission is requested and no calendar data is read or written (§15).';

create index if not exists style_events_user_date_idx
  on public.style_events (user_id, event_at);
-- The reminder cron scans forward only, and only for events that opted in.
create index if not exists style_events_reminder_idx
  on public.style_events (event_at) where reminder_opt_in;

alter table public.style_events enable row level security;

drop policy if exists style_events_select_own on public.style_events;
create policy style_events_select_own on public.style_events
  for select using (auth.uid() = user_id);

drop policy if exists style_events_insert_own on public.style_events;
create policy style_events_insert_own on public.style_events
  for insert with check (auth.uid() = user_id);

drop policy if exists style_events_update_own on public.style_events;
create policy style_events_update_own on public.style_events
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists style_events_delete_own on public.style_events;
create policy style_events_delete_own on public.style_events
  for delete using (auth.uid() = user_id);

do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    drop trigger if exists style_events_set_updated_at on public.style_events;
    create trigger style_events_set_updated_at
      before update on public.style_events
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- ── flags, seeded OFF ────────────────────────────────────────────────────────
insert into public.feature_flags (key, enabled, description)
values
  ('feature_mood_planner_v2', false,
   'Mood Planner v2: pick a mood + occasion, get styling direction with no render.'),
  ('feature_event_planner', false,
   'Event Planner: save an event with a date, occasion and look.'),
  ('feature_personalized_home_v2', false,
   'Maturity-aware Home composition. OFF = current Home, unchanged.')
on conflict (key) do nothing;
