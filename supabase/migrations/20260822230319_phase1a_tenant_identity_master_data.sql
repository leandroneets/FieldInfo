-- Phase 1a — tenant root, identity, and master data.
--
-- Replaces the prototype's master-data tables rather than mutating them
-- (ADR-012). Everything created here follows the standard laid out in
-- CLAUDE.md: client-generated UUID primary keys, org_id on every row,
-- timestamptz only, soft delete, and a revision counter maintained by trigger.
--
-- RLS is enabled with no policies, preserving the deny-all floor established in
-- 20260809052924 (ADR-013). Phase 2 adds the real policies.

-- ---------------------------------------------------------------------------
-- 0. Remove the prototype schema.
--
-- Safe because the database has never held production data (7 test rows at the
-- time of writing) and Phase 1 replaces this schema in full. `cascade` also
-- takes the prototype's foreign keys, indexes and the trg_semeadura_bump
-- trigger with it.
--
-- semeadura_changes_since() is dropped outright here rather than merely being
-- made unreachable, as ADR-013 anticipated: it is a hand-rolled incremental
-- sync that PowerSync supersedes (ADR-002).
-- ---------------------------------------------------------------------------

drop function if exists public.semeadura_changes_since(timestamptz);

drop table if exists public.semeadura      cascade;
drop table if exists public.usuario_plano  cascade;
drop table if exists public.plano_producao cascade;
drop table if exists public.usuarios       cascade;
drop table if exists public.material       cascade;
drop table if exists public.safra          cascade;

drop function if exists public.bump_revision();

-- ---------------------------------------------------------------------------
-- 1. Shared trigger: updated_at / updated_by / revision.
--
-- Fires BEFORE UPDATE only. `revision` starts at 1 on insert (column default)
-- and increments here, so a device pushing an edit based on revision N can be
-- detected as stale when the server already sits at N+1 — the mechanism Phase 8
-- conflict detection depends on (ADR-006).
--
-- `set search_path = ''` pins name resolution so the function cannot be
-- redirected by a caller-controlled search_path. Identifiers inside are
-- therefore schema-qualified.
-- ---------------------------------------------------------------------------

create or replace function public.set_row_metadata()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  new.revision   := coalesce(old.revision, 0) + 1;
  return new;
end;
$fn$;

comment on function public.set_row_metadata() is
  'BEFORE UPDATE trigger: stamps updated_at/updated_by and increments revision.';

-- ---------------------------------------------------------------------------
-- 2. organizacao — the tenant root (ADR-003).
--
-- org_id is carried even here, constrained to equal the row's own id. That
-- keeps the "every synced table has org_id" invariant literally true, which
-- matters because PowerSync Sync Rules bucket on one consistent column name
-- across all tables.
--
-- created_by is nullable on this table alone: the first organizacao must exist
-- before any usuario can reference it, so the bootstrap row has no author.
-- ---------------------------------------------------------------------------

create table public.organizacao (
  id          uuid        primary key,
  org_id      uuid        not null,
  nome        text        not null,
  ativa       boolean     not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid,
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,
  constraint organizacao_org_id_is_self check (org_id = id),
  constraint organizacao_nome_nao_vazio check (length(trim(nome)) > 0)
);

comment on table public.organizacao is 'Tenant root. One row per company using the system.';

-- ---------------------------------------------------------------------------
-- 3. usuario — identity keyed to auth.users.id (ADR-008).
--
-- id IS auth.users.id, so RLS policies reach it through auth.uid() directly and
-- never through a mutable column. The prototype's standalone id_usuario is
-- precisely what made its semeadura policy unsatisfiable.
--
-- `email` is a cached copy for offline display and search. It is deliberately
-- NOT a key and must never appear in an authorization check — Supabase Auth
-- remains the source of truth and the address can change there.
--
-- `papel` holds unaccented lowercase identifiers, not display strings. The
-- Portuguese labels the technician sees come from ARB files.
-- ---------------------------------------------------------------------------

create table public.usuario (
  id          uuid        primary key references auth.users(id) on delete restrict,
  org_id      uuid        not null references public.organizacao(id) on delete restrict,
  nome        text        not null,
  email       text        not null,
  papel       text        not null,
  ativo       boolean     not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid        references public.usuario(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,
  constraint usuario_papel_valido    check (papel in ('tecnico', 'supervisor', 'suporte')),
  constraint usuario_nome_nao_vazio  check (length(trim(nome)) > 0)
);

comment on table  public.usuario       is 'Application identity. id equals auth.users.id (ADR-008).';
comment on column public.usuario.email is 'Cached from auth for offline display. Never used for authorization.';

-- organizacao.created_by could not be declared until usuario existed.
alter table public.organizacao
  add constraint organizacao_created_by_fkey
  foreign key (created_by) references public.usuario(id);

-- ---------------------------------------------------------------------------
-- 4. safra — season. Master data.
--
-- `codigo` is the legacy Cod_safra (e.g. 2026/2027), unique within a tenant
-- rather than globally: two companies may legitimately use the same label.
-- ---------------------------------------------------------------------------

create table public.safra (
  id          uuid        primary key,
  org_id      uuid        not null references public.organizacao(id) on delete restrict,
  codigo      text        not null,
  data_inicio date,
  data_fim    date,
  ativa       boolean     not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid        not null references public.usuario(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,
  constraint safra_codigo_unico_por_org unique (org_id, codigo),
  constraint safra_periodo_coerente check (
    data_fim is null or data_inicio is null or data_inicio <= data_fim
  )
);

-- ---------------------------------------------------------------------------
-- 5. material — hybrid. Master data.
--
-- macho and femea are the parent lines whose flowering must coincide; they are
-- why planting windows are high-value data (docs/DOMAIN.md).
--
-- umidade_min/max are numeric(5,2), NOT the legacy decimal(18,0). The source
-- system stored zero decimal places, so a 12.4% threshold became 12 — and these
-- values gate harvest release.
-- ---------------------------------------------------------------------------

create table public.material (
  id          uuid        primary key,
  org_id      uuid        not null references public.organizacao(id) on delete restrict,
  hibrido     text        not null,
  macho       text        not null,
  femea       text        not null,
  cultura     text,
  umidade_min numeric(5,2),
  umidade_max numeric(5,2),
  created_at  timestamptz not null default now(),
  created_by  uuid        not null references public.usuario(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,
  constraint material_hibrido_unico_por_org unique (org_id, hibrido),
  constraint material_umidade_coerente check (
    umidade_min is null or umidade_max is null or umidade_min <= umidade_max
  ),
  constraint material_umidade_plausivel check (
    (umidade_min is null or umidade_min between 0 and 100) and
    (umidade_max is null or umidade_max between 0 and 100)
  )
);

-- ---------------------------------------------------------------------------
-- 6. Triggers.
-- ---------------------------------------------------------------------------

create trigger trg_organizacao_metadata before update on public.organizacao
  for each row execute function public.set_row_metadata();

create trigger trg_usuario_metadata before update on public.usuario
  for each row execute function public.set_row_metadata();

create trigger trg_safra_metadata before update on public.safra
  for each row execute function public.set_row_metadata();

create trigger trg_material_metadata before update on public.material
  for each row execute function public.set_row_metadata();

-- ---------------------------------------------------------------------------
-- 7. Indexes.
--
-- Every RLS policy Phase 2 writes will filter on org_id, and every sync bucket
-- will too. Partial on `deleted_at is null` because live rows are what both
-- paths actually read.
-- ---------------------------------------------------------------------------

create index idx_usuario_org  on public.usuario(org_id)  where deleted_at is null;
create index idx_safra_org    on public.safra(org_id)    where deleted_at is null;
create index idx_material_org on public.material(org_id) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 8. Deny-all floor preserved (ADR-013). Policies arrive in Phase 2.
-- ---------------------------------------------------------------------------

alter table public.organizacao enable row level security;
alter table public.usuario     enable row level security;
alter table public.safra       enable row level security;
alter table public.material    enable row level security;
