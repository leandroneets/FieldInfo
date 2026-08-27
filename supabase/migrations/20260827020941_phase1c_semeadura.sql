-- Phase 1c — semeadura and its immediate children.
--
-- semeadura is the only Class C entity in the system (ADR-006): one row per
-- field, edited incrementally over weeks, with real conflict risk. Everything
-- here is shaped around that.
--
-- Vocabulary columns reference parametro through the generated-constant +
-- composite-FK pattern established in ADR-014, so the database rejects a value
-- absent from the right domain and the right tenant.

-- ---------------------------------------------------------------------------
-- 1. semeadura — one per field.
--
-- The legacy model keyed this on (id_semeadura, id_plano) and additionally
-- carried NumCampo with its own foreign key, giving two independent paths to
-- the same parent that nothing forced to agree. Here there is one: id_plano,
-- unique, so "one semeadura per field" is enforced rather than assumed.
--
-- proporcao_semeadura is text, not numeric. It holds a ratio such as '4:1'
-- (four female rows to one male). The prototype's numeric column would have
-- silently destroyed that value.
--
-- The espacamento measures are numeric(4,2) — metres between rows, so 99.99 is
-- a generous ceiling.
-- ---------------------------------------------------------------------------

create table public.semeadura (
  id                       uuid        primary key,
  org_id                   uuid        not null references public.organizacao(id)    on delete restrict,
  id_plano                 uuid        not null references public.plano_producao(id) on delete restrict,

  data_liberacao_pivo      date,
  inicio_semeadura_femea   date,
  fim_semeadura_femea      date,
  inicio_semeadura_macho1  date,
  fim_semeadura_macho1     date,
  inicio_semeadura_macho2  date,
  fim_semeadura_macho2     date,
  inicio_semeadura_macho3  date,
  fim_semeadura_macho3     date,

  espacamento_mxm          numeric(4,2),
  espacamento_fxm          numeric(4,2),
  espacamento_fxf          numeric(4,2),
  proporcao_semeadura      text,

  status_semeadura         text,
  tipo_espacamento         text,
  tipo_lancamento          text,
  observacao               text,

  created_at               timestamptz not null default now(),
  created_by               uuid        not null references public.usuario(id),
  updated_at               timestamptz not null default now(),
  updated_by               uuid,
  revision                 bigint      not null default 1,
  deleted_at               timestamptz,

  constraint semeadura_uma_por_plano unique (id_plano),

  constraint semeadura_janela_femea check (
    fim_semeadura_femea is null or inicio_semeadura_femea is null
    or inicio_semeadura_femea <= fim_semeadura_femea),
  constraint semeadura_janela_macho1 check (
    fim_semeadura_macho1 is null or inicio_semeadura_macho1 is null
    or inicio_semeadura_macho1 <= fim_semeadura_macho1),
  constraint semeadura_janela_macho2 check (
    fim_semeadura_macho2 is null or inicio_semeadura_macho2 is null
    or inicio_semeadura_macho2 <= fim_semeadura_macho2),
  constraint semeadura_janela_macho3 check (
    fim_semeadura_macho3 is null or inicio_semeadura_macho3 is null
    or inicio_semeadura_macho3 <= fim_semeadura_macho3),

  constraint semeadura_espacamentos_positivos check (
    (espacamento_mxm is null or espacamento_mxm > 0) and
    (espacamento_fxm is null or espacamento_fxm > 0) and
    (espacamento_fxf is null or espacamento_fxf > 0))
);

-- Vocabulary columns. NULL stays legal everywhere: the composite FK is MATCH
-- SIMPLE, and 'no status yet' is a real state — the field team confirmed the
-- status domain is (null, Plantando, Finalizado).
alter table public.semeadura
  add column status_dominio     text generated always as ('status_semeadura') stored,
  add column espacamento_dominio text generated always as ('tipo_espacamento') stored,
  add column lancamento_dominio  text generated always as ('tipo_lancamento')  stored;

alter table public.semeadura
  add constraint semeadura_status_fk
    foreign key (org_id, status_dominio, status_semeadura)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint semeadura_tipo_espacamento_fk
    foreign key (org_id, espacamento_dominio, tipo_espacamento)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint semeadura_tipo_lancamento_fk
    foreign key (org_id, lancamento_dominio, tipo_lancamento)
    references public.parametro(org_id, dominio, codigo) on delete restrict;

comment on table  public.semeadura                     is 'One planting record per field. Class C — mutable, conflict-prone (ADR-006).';
comment on column public.semeadura.proporcao_semeadura is 'Planting ratio as text, e.g. 4:1. Never numeric.';

-- ---------------------------------------------------------------------------
-- 2. semeadura_basica — basic seed lots used for this planting.
--
-- Confirmed as técnico-written, so it syncs to the device and needs conflict
-- rules, not download-only treatment.
--
-- The kg columns are numeric(10,2), not the legacy decimal(4,2). That capped a
-- lot at 99.99 kg, which is implausibly small for a field's seed quantity — the
-- same class of silent truncation as the decimal(18,0) moisture columns.
-- ---------------------------------------------------------------------------

create table public.semeadura_basica (
  id                     uuid        primary key,
  org_id                 uuid        not null references public.organizacao(id) on delete restrict,
  id_semeadura           uuid        not null references public.semeadura(id)   on delete restrict,

  lote_basica_femea      text,
  kg_femea               numeric(10,2),
  lote_femea_esteril     text,
  peneira_femea_esteril  text,
  kg_femea_esteril       numeric(10,2),
  geracao                text,
  lote_basica_macho      text,
  peneira_macho          text,
  kg_macho               numeric(10,2),
  nota_fiscal_femea      text,
  nota_fiscal_macho      text,

  created_at             timestamptz not null default now(),
  created_by             uuid        not null references public.usuario(id),
  updated_at             timestamptz not null default now(),
  updated_by             uuid,
  revision               bigint      not null default 1,
  deleted_at             timestamptz,

  constraint semeadura_basica_kg_positivo check (
    (kg_femea         is null or kg_femea         > 0) and
    (kg_femea_esteril is null or kg_femea_esteril > 0) and
    (kg_macho         is null or kg_macho         > 0))
);

-- ---------------------------------------------------------------------------
-- 3. estadio_fenologico — append-only observation (Class A).
--
-- Reached through id_semeadura alone. The legacy model carried id_plano too,
-- but semeadura is unique per plano, so the second column added no information
-- and a way to disagree.
-- ---------------------------------------------------------------------------

create table public.estadio_fenologico (
  id                uuid        primary key,
  org_id            uuid        not null references public.organizacao(id) on delete restrict,
  id_semeadura      uuid        not null references public.semeadura(id)   on delete restrict,
  estadio           text        not null,
  data_apontamento  date        not null,
  observacao        text,
  gerar_alerta      boolean     not null default false,

  created_at        timestamptz not null default now(),
  created_by        uuid        not null references public.usuario(id),
  updated_at        timestamptz not null default now(),
  updated_by        uuid,
  revision          bigint      not null default 1,
  deleted_at        timestamptz
);

alter table public.estadio_fenologico
  add column estadio_dominio text generated always as ('estadio_fenologico') stored;

alter table public.estadio_fenologico
  add constraint estadio_fenologico_estadio_fk
    foreign key (org_id, estadio_dominio, estadio)
    references public.parametro(org_id, dominio, codigo) on delete restrict;

comment on table public.estadio_fenologico is 'Append-only phenological observation (Class A, ADR-006).';

-- ---------------------------------------------------------------------------
-- 4. Triggers, indexes, RLS floor.
-- ---------------------------------------------------------------------------

create trigger trg_semeadura_metadata before update on public.semeadura
  for each row execute function public.set_row_metadata();
create trigger trg_semeadura_basica_metadata before update on public.semeadura_basica
  for each row execute function public.set_row_metadata();
create trigger trg_estadio_fenologico_metadata before update on public.estadio_fenologico
  for each row execute function public.set_row_metadata();

create index idx_semeadura_org           on public.semeadura(org_id)                   where deleted_at is null;
create index idx_semeadura_plano         on public.semeadura(id_plano)                 where deleted_at is null;
create index idx_semeadura_basica_org    on public.semeadura_basica(org_id)            where deleted_at is null;
create index idx_semeadura_basica_sem    on public.semeadura_basica(id_semeadura)      where deleted_at is null;
create index idx_estadio_org             on public.estadio_fenologico(org_id)          where deleted_at is null;
create index idx_estadio_sem             on public.estadio_fenologico(id_semeadura, data_apontamento desc) where deleted_at is null;

alter table public.semeadura          enable row level security;
alter table public.semeadura_basica   enable row level security;
alter table public.estadio_fenologico enable row level security;
