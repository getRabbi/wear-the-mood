-- 0066 — explicit, versioned, revocable consent for sending a user's own photo
-- to a third-party AI provider.
--
-- WHY A SECOND CONSENT TABLE, AND NOT A COLUMN ON `consents`.
--
-- `public.consents` already records the §10 biometric-CAPTURE consent: "you may
-- take and store my face/body photo". It is append-only, has no revoke column,
-- and versions as free text. That consent answers a question about CAPTURE. It
-- has never answered the different question Apple's Guideline 5.1.1(i) asks:
--
--   may this photo LEAVE Wear The Mood and be processed by a named third party?
--
-- Those are separately withdrawable — a user may keep their body photo in the
-- app and still refuse to have it sent out for a render — so they need separate
-- state. Overloading the capture record would have made "withdraw AI sharing"
-- indistinguishable from "delete my body photo", which is the opposite of what
-- the user asked for.
--
-- SHAPE: one CURRENT row per (user, consent_type), updated in place. The grant
-- timeline that matters legally is on the row itself (granted_at / revoked_at /
-- updated_at), and a single row makes "is consent currently valid at version N"
-- one indexed read on the hot path of every AI submit.
--
-- Additive and idempotent; safe to re-run. Nothing here reads or writes
-- `public.consents`, so the biometric gate is untouched.

create table if not exists public.user_privacy_consents (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  -- Semantic key, not a screen name: the same consent covers every feature that
  -- ships a personal image to a third-party AI provider.
  consent_type    text not null,
  -- Integer, so "is the stored grant older than what we now require" is an
  -- ordinary comparison. Bumped when the provider, purpose or scope materially
  -- changes, which re-asks the user exactly once.
  consent_version integer not null,
  -- WHO the user agreed may receive it, recorded as granted rather than assumed
  -- from today's config — so a later provider change is visible in the data and
  -- cannot silently inherit an old agreement.
  provider_scope  text not null,
  granted_at      timestamptz not null default now(),
  -- Null means currently granted. Set on withdrawal; cleared on re-grant.
  revoked_at      timestamptz,
  updated_at      timestamptz not null default now(),
  constraint user_privacy_consents_user_type_uniq unique (user_id, consent_type)
);

-- The only lookup on the hot path: "this user, this consent type".
create index if not exists user_privacy_consents_user_idx
  on public.user_privacy_consents (user_id, consent_type);

alter table public.user_privacy_consents enable row level security;

-- Own-row only (§11), matching the pattern every other user-owned table uses.
-- The API writes with the service role and always scopes by the JWT's user id;
-- this is the defence-in-depth layer under it.
drop policy if exists user_privacy_consents_rw_own on public.user_privacy_consents;
create policy user_privacy_consents_rw_own on public.user_privacy_consents
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Keep updated_at honest without every caller remembering to set it.
create or replace function public.touch_user_privacy_consents()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists user_privacy_consents_touch on public.user_privacy_consents;
create trigger user_privacy_consents_touch
  before update on public.user_privacy_consents
  for each row execute function public.touch_user_privacy_consents();

-- WHICH consent a job was submitted under.
--
-- Recorded so a render that was authorised at submit stays authorised: the
-- worker retries a job it already accepted rather than re-asking the database
-- whether consent is still current, which would fail an in-flight job the user
-- had every right to start. It is also the audit answer to "under what terms was
-- this specific image shared" without storing anything about the image itself.
--
-- Nullable: rows that predate this migration were submitted before the consent
-- existed and must not be back-dated into looking like they had one.
alter table public.tryon_jobs
  add column if not exists consent_version integer;

comment on column public.tryon_jobs.consent_version is
  'AI data-sharing consent version in force when this job was accepted; null for '
  'jobs submitted before 0066 or for renders that carry no personal image.';
