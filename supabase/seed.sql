-- Bootstrap data for a freshly migrated database.
--
-- Creates the first organizacao and links the existing Supabase Auth users to
-- it, so role routing has something to resolve after Phase 1a wiped the
-- prototype's usuarios table.
--
-- Run as `postgres` (or service_role) — every table here is RLS-enabled with a
-- deny-all floor until Phase 2, so an ordinary role cannot insert.
--
-- Idempotent: re-running changes nothing. Safe to apply repeatedly.
--
-- No local Supabase stack is running (no Docker), so this is applied directly:
--
--   psql "<connection string>" -f supabase/seed.sql
--
-- ---------------------------------------------------------------------------

-- Fixed UUID so the seed stays idempotent across runs. Real records use
-- client-generated UUIDv4 (ADR-009); this is a bootstrap constant, not a
-- pattern to copy.
insert into public.organizacao (id, org_id, nome)
values (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000001',
  'FieldInfo — organização de desenvolvimento'
)
on conflict (id) do nothing;

-- Users are matched to auth.users by email rather than by hardcoded uuid, so
-- this still works if the auth users are ever recreated.
--
-- ASSUMPTION: the roles below are a guess. The prototype's tipo_usuario values
-- were dropped with the usuarios table before they could be read. Adjust the
-- `papel` column here and re-run if either is wrong.
with bootstrap(email, nome, papel) as (
  values
    ('leandro_neets@hotmail.com', 'Leandro',       'suporte'),
    ('euseiqehspam@gmail.com',    'Técnico Teste', 'tecnico')
)
insert into public.usuario (id, org_id, nome, email, papel)
select
  a.id,
  '00000000-0000-4000-8000-000000000001',
  b.nome,
  a.email,
  b.papel
from bootstrap b
join auth.users a on a.email = b.email
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Domain vocabulary for the bootstrap organizacao.
--
-- This lives in the seed rather than in a migration because parametro rows are
-- tenant data, and migrations must stay tenant-agnostic. A consequence worth
-- knowing: onboarding a second organizacao needs its own vocabulary, so org
-- creation (the Phase 5 Edge Function) has to copy these defaults. Until then,
-- only the bootstrap org has a usable set.
--
-- `codigo` is what child rows store and must not change. `rotulo` is display
-- and can be corrected at will.
-- ---------------------------------------------------------------------------

-- Phenological stages, in biological order: vegetative V1–V11, detasseling,
-- then reproductive R1–R6.
--
-- The source dropdown also contained an empty string. It is deliberately not
-- seeded: it was a "nothing selected" placeholder, and storing it would create
-- a value indistinguishable from "not answered" that still sorts and groups
-- like a real stage. The column is nullable instead.
--
-- The source also read 'Despendoamento.' with a trailing period the other
-- eighteen values do not have. Stored without it.
insert into public.parametro (id, org_id, dominio, codigo, rotulo, ordem, created_by)
select
  gen_random_uuid(),
  '00000000-0000-4000-8000-000000000001',
  'estadio_fenologico',
  v.codigo,
  v.codigo,
  v.ordem,
  (select id from public.usuario where papel = 'suporte' order by created_at limit 1)
from (values
  ('V1',1),  ('V2',2),  ('V3',3),  ('V4',4),  ('V5',5),  ('V6',6),
  ('V7',7),  ('V8',8),  ('V9',9),  ('V10',10),('V11',11),
  ('Despendoamento',12),
  ('R1',13), ('R2',14), ('R3',15), ('R4',16), ('R5',17), ('R6',18)
) as v(codigo, ordem)
on conflict (org_id, dominio, codigo) do nothing;

-- Planting status. NULL means "not started" and is deliberately not a seeded
-- value — the column is nullable instead, so "no status yet" cannot be confused
-- with a status the técnico actively chose.
--
-- bloqueia_edicao marks the point where the record stops being the technician's
-- to edit (ADR-006). Phase 8 reads this flag, never the label, so renaming
-- 'Finalizado' can never silently disable the lock.
--
-- Casing normalised to title case for both values; the source list mixed
-- 'Plantando' with 'finalizado'. codigo is permanent, so this is settled here
-- rather than inherited.
insert into public.parametro (id, org_id, dominio, codigo, rotulo, ordem, bloqueia_edicao, created_by)
select
  gen_random_uuid(),
  '00000000-0000-4000-8000-000000000001',
  'status_semeadura',
  v.codigo,
  v.codigo,
  v.ordem,
  v.bloqueia,
  (select id from public.usuario where papel = 'suporte' order by created_at limit 1)
from (values
  ('Plantando',  1, false),
  ('Finalizado', 2, true)
) as v(codigo, ordem, bloqueia)
on conflict (org_id, dominio, codigo) do nothing;

-- Harvest mode. Migrated off the CHECK constraint added in 20260823050658.
insert into public.parametro (id, org_id, dominio, codigo, rotulo, ordem, created_by)
select
  gen_random_uuid(),
  '00000000-0000-4000-8000-000000000001',
  'modo_colheita',
  v.codigo,
  v.codigo,
  v.ordem,
  (select id from public.usuario where papel = 'suporte' order by created_at limit 1)
from (values ('AXF',1), ('Espiga',2)) as v(codigo, ordem)
on conflict (org_id, dominio, codigo) do nothing;
