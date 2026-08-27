-- Admin-managed domain vocabulary.
--
-- Replaces hardcoded CHECK constraints for value lists that the business owns
-- rather than the schema: planting status, phenological stage, spacing type,
-- harvest mode, and so on. A suporte user adds a value through the app instead
-- of waiting for a migration.
--
-- Two reasons this is a table and not a CHECK:
--
--   1. docs/DOMAIN.md requires every reference dropdown to work with zero
--      connectivity, status values included. A CHECK constraint cannot populate
--      a dropdown, so the list would have to be duplicated in Dart — and the
--      two copies would drift.
--   2. Adding a phenological stage should not require a deploy.
--
-- Integrity is preserved, not traded away. Consuming columns use a generated
-- constant column plus a composite foreign key, so Postgres rejects a value
-- that does not exist in the right domain AND the right tenant. Application
-- code is not trusted to validate.
--
-- WHERE THE LINE IS: domain vocabulary lives here; anything RLS reads stays in
-- the schema. usuario.papel is deliberately NOT migrated — if suporte can
-- insert parametro rows and roles were parametro rows, suporte could mint
-- itself a new role. That is privilege escalation by data entry.

-- ---------------------------------------------------------------------------
-- 1. parametro
--
-- codigo vs rotulo: `codigo` is the stored value that foreign keys point at and
-- that history is written in — stable, never renamed. `rotulo` is what the
-- técnico reads and may be corrected freely, because no row depends on it.
-- Correcting a typo is then a label edit, not a rewrite of every child record.
--
-- This makes admin-defined vocabulary a deliberate exception to the CLAUDE.md
-- rule that all user-facing strings live in ARB files. ARB is compiled into the
-- app; these strings are tenant data and cannot be.
--
-- bloqueia_edicao exists because behaviour must never be inferred from a name.
-- ADR-006 locks a semeadura once completed or approved. That lock keys off this
-- explicit flag, never off a status happening to be called 'Concluída' —
-- otherwise renaming a status would silently disable the lock.
--
-- ativo retires a value: it disappears from new dropdowns while existing rows
-- still resolve. Combined with ON DELETE RESTRICT, a value in use cannot be
-- destroyed (ADR-005).
-- ---------------------------------------------------------------------------

create table public.parametro (
  id              uuid        primary key,
  org_id          uuid        not null references public.organizacao(id) on delete restrict,
  dominio         text        not null,
  codigo          text        not null,
  rotulo          text        not null,
  ordem           integer     not null default 0,
  ativo           boolean     not null default true,
  bloqueia_edicao boolean     not null default false,
  created_at      timestamptz not null default now(),
  created_by      uuid        not null references public.usuario(id),
  updated_at      timestamptz not null default now(),
  updated_by      uuid,
  revision        bigint      not null default 1,
  deleted_at      timestamptz,
  constraint parametro_codigo_unico_por_dominio unique (org_id, dominio, codigo),
  constraint parametro_dominio_nao_vazio check (length(trim(dominio)) > 0),
  constraint parametro_codigo_nao_vazio  check (length(trim(codigo))  > 0),
  constraint parametro_rotulo_nao_vazio  check (length(trim(rotulo))  > 0)
);

comment on table  public.parametro                 is 'Admin-managed domain vocabulary, scoped per tenant.';
comment on column public.parametro.codigo          is 'Stored value. Stable — foreign keys reference it. Never rename.';
comment on column public.parametro.rotulo          is 'Display label. Safe to correct; nothing references it.';
comment on column public.parametro.bloqueia_edicao is 'Value locks the parent record against further edits (ADR-006).';
comment on column public.parametro.ativo           is 'False retires the value from new entry while old rows still resolve.';

create trigger trg_parametro_metadata before update on public.parametro
  for each row execute function public.set_row_metadata();

create index idx_parametro_org     on public.parametro(org_id) where deleted_at is null;
create index idx_parametro_dominio on public.parametro(org_id, dominio, ordem) where deleted_at is null and ativo;

alter table public.parametro enable row level security;

-- ---------------------------------------------------------------------------
-- 2. Move plano_producao.modo_colheita onto the new mechanism.
--
-- The CHECK added in 20260823050658 has to go: leaving it in place would mean
-- two authorities disagreeing, and adding a third harvest mode through the
-- admin screen would still be rejected by the constraint.
--
-- modo_colheita stays nullable. The composite FK uses MATCH SIMPLE (the
-- default), under which a NULL in any referencing column satisfies the
-- constraint — so "not decided yet" remains representable.
-- ---------------------------------------------------------------------------

alter table public.plano_producao
  drop constraint plano_modo_colheita_valido;

alter table public.plano_producao
  add column modo_colheita_dominio text
  generated always as ('modo_colheita') stored;

alter table public.plano_producao
  add constraint plano_modo_colheita_fk
  foreign key (org_id, modo_colheita_dominio, modo_colheita)
  references public.parametro(org_id, dominio, codigo)
  on delete restrict;

comment on column public.plano_producao.modo_colheita is
  'References parametro where dominio = modo_colheita. NULL until decided.';
