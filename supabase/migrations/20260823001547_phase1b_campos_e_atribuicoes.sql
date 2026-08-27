-- Phase 1b — farms, fields, production plans, and technician assignments.
--
-- Continues the conventions established in 20260822230319: client-generated
-- UUID keys, org_id everywhere, timestamptz, soft delete, revision by trigger,
-- RLS on with no policies (Phase 2 supplies those).
--
-- ---------------------------------------------------------------------------
-- DESIGN NOTE — fazenda and gleba are separate tables.
--
-- The legacy SQL Server model and the prototype both stored Fazenda, Gleba,
-- Setor and Hectare as loose columns on the plan row. docs/ASSESSMENT.md flags
-- that collapse as a finding, and docs/DOMAIN.md lists fazenda and gleba/campo
-- as master-data entities in their own right.
--
-- Normalising them means a farm renamed once is renamed everywhere, a gleba
-- can carry its own attributes later, and "show me every plan on this farm" is
-- a join rather than a string match. The cost is two more tables to sync and
-- an extra hop when displaying a plan.
--
-- Hectare and Setor stay on plano_producao: they describe the planted area for
-- this season's plan, not a permanent property of the gleba.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. fazenda — farm. Master data.
--
-- `cooperado` is the grower/cooperative member the farm belongs to, carried
-- over from the legacy TB_PLANOPRODUCAO.Cooperado column. It sits here rather
-- than on the plan because it is a property of the farm, not of one season.
-- ---------------------------------------------------------------------------

create table public.fazenda (
  id          uuid        primary key,
  org_id      uuid        not null references public.organizacao(id) on delete restrict,
  nome        text        not null,
  cooperado   text,
  created_at  timestamptz not null default now(),
  created_by  uuid        not null references public.usuario(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,
  constraint fazenda_nome_unico_por_org unique (org_id, nome),
  constraint fazenda_nome_nao_vazio     check (length(trim(nome)) > 0)
);

comment on column public.fazenda.cooperado is 'Grower / cooperative member the farm belongs to.';

-- ---------------------------------------------------------------------------
-- 2. gleba — the field within a farm. Master data.
-- ---------------------------------------------------------------------------

create table public.gleba (
  id          uuid        primary key,
  org_id      uuid        not null references public.organizacao(id) on delete restrict,
  id_fazenda  uuid        not null references public.fazenda(id) on delete restrict,
  nome        text        not null,
  created_at  timestamptz not null default now(),
  created_by  uuid        not null references public.usuario(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,
  constraint gleba_nome_unico_por_fazenda unique (id_fazenda, nome),
  constraint gleba_nome_nao_vazio         check (length(trim(nome)) > 0)
);

-- ---------------------------------------------------------------------------
-- 3. plano_producao — one field, one season, one hybrid.
--
-- num_campo is the number the field team actually says out loud, and it is
-- unique per tenant per season. The prototype had no uniqueness at all
-- (docs/ASSESSMENT.md); the legacy model had it globally unique, which breaks
-- as soon as a second season reuses a number.
--
-- id_safra + id_material + id_gleba replace the legacy Cod_safra / Hibrido /
-- Fazenda+Gleba text columns.
--
-- modo_colheita is left as free text deliberately: the allowed values are not
-- yet known. It should become a CHECK constraint once the field team confirms
-- them — free-text status columns are a MEDIUM finding in ASSESSMENT.md and
-- this one is a knowingly temporary exception.
-- ---------------------------------------------------------------------------

create table public.plano_producao (
  id            uuid        primary key,
  org_id        uuid        not null references public.organizacao(id) on delete restrict,
  id_safra      uuid        not null references public.safra(id)       on delete restrict,
  id_material   uuid        not null references public.material(id)    on delete restrict,
  id_gleba      uuid        not null references public.gleba(id)       on delete restrict,
  num_campo     integer     not null,
  hectare       numeric(10,2),
  setor         text,
  modo_colheita text,
  ativo         boolean     not null default true,
  created_at    timestamptz not null default now(),
  created_by    uuid        not null references public.usuario(id),
  updated_at    timestamptz not null default now(),
  updated_by    uuid,
  revision      bigint      not null default 1,
  deleted_at    timestamptz,
  constraint plano_num_campo_unico_por_safra unique (org_id, id_safra, num_campo),
  constraint plano_hectare_positivo check (hectare is null or hectare > 0),
  constraint plano_num_campo_positivo check (num_campo > 0)
);

comment on column public.plano_producao.modo_colheita is
  'Free text pending confirmation of allowed values; should become a CHECK constraint.';

-- ---------------------------------------------------------------------------
-- 4. usuario_plano — which technician is responsible for which field.
--
-- This is the table PowerSync Sync Rules will read to decide what reaches a
-- technician's device, and the table Phase 2 policies will consult for
-- authorization. It replaces the legacy emailTecnico columns scattered across
-- nine tables, which keyed responsibility to a mutable address with no foreign
-- key behind it (ADR-008).
--
-- The unique constraint the prototype already had is preserved.
-- ---------------------------------------------------------------------------

create table public.usuario_plano (
  id          uuid        primary key,
  org_id      uuid        not null references public.organizacao(id)    on delete restrict,
  id_usuario  uuid        not null references public.usuario(id)        on delete restrict,
  id_plano    uuid        not null references public.plano_producao(id) on delete restrict,
  created_at  timestamptz not null default now(),
  created_by  uuid        not null references public.usuario(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,
  constraint usuario_plano_atribuicao_unica unique (id_usuario, id_plano)
);

-- ---------------------------------------------------------------------------
-- 5. Triggers.
-- ---------------------------------------------------------------------------

create trigger trg_fazenda_metadata before update on public.fazenda
  for each row execute function public.set_row_metadata();

create trigger trg_gleba_metadata before update on public.gleba
  for each row execute function public.set_row_metadata();

create trigger trg_plano_producao_metadata before update on public.plano_producao
  for each row execute function public.set_row_metadata();

create trigger trg_usuario_plano_metadata before update on public.usuario_plano
  for each row execute function public.set_row_metadata();

-- ---------------------------------------------------------------------------
-- 6. Indexes.
--
-- org_id for RLS and sync bucketing; the foreign keys that drive the two hot
-- read paths — "the fields assigned to me" and "the plans on this gleba".
-- ---------------------------------------------------------------------------

create index idx_fazenda_org        on public.fazenda(org_id)            where deleted_at is null;
create index idx_gleba_org          on public.gleba(org_id)              where deleted_at is null;
create index idx_gleba_fazenda      on public.gleba(id_fazenda)          where deleted_at is null;
create index idx_plano_org          on public.plano_producao(org_id)     where deleted_at is null;
create index idx_plano_safra        on public.plano_producao(id_safra)   where deleted_at is null;
create index idx_plano_gleba        on public.plano_producao(id_gleba)   where deleted_at is null;
create index idx_usuario_plano_org  on public.usuario_plano(org_id)      where deleted_at is null;
create index idx_usuario_plano_user on public.usuario_plano(id_usuario)  where deleted_at is null;
create index idx_usuario_plano_plan on public.usuario_plano(id_plano)    where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 7. Deny-all floor preserved (ADR-013).
-- ---------------------------------------------------------------------------

alter table public.fazenda        enable row level security;
alter table public.gleba          enable row level security;
alter table public.plano_producao enable row level security;
alter table public.usuario_plano  enable row level security;
