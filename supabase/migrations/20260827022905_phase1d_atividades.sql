-- Phase 1d — the remaining field activities.
--
-- bioensaio and its checklist, moisture sampling, harvest sheets and loads,
-- and production alerts. Completes the Phase 1 schema.
--
-- All Class A append-only (ADR-006) except carga, which carries a completion
-- flag, and ficha_colheita / alerta_producao, which are server-authoritative:
-- they reach the device read-only and the app never writes them.
--
-- Vocabulary columns reference parametro (ADR-014) and are nullable. Their
-- domains are created empty — the value lists are not yet known, and an empty
-- domain means only NULL is accepted until suporte populates it through the
-- admin screen. That is deliberate: an unpopulated domain fails closed.

-- ---------------------------------------------------------------------------
-- 1. bioensaio_checklist — site history assessed before the bioassay.
--
-- These are the real items from the legacy TB_CHECKLISTBIOENSAIO, which is the
-- best answer available to the "what does the bioassay checklist contain?"
-- question left open in docs/DOMAIN.md.
--
-- Booleans are nullable throughout: "not assessed" is distinct from "no", and
-- the legacy columns were nullable for the same reason.
--
-- HoraInput is dropped in favour of the standard created_at, which is
-- timestamptz rather than the legacy datetime.
-- ---------------------------------------------------------------------------

create table public.bioensaio_checklist (
  id                        uuid        primary key,
  org_id                    uuid        not null references public.organizacao(id)    on delete restrict,
  id_plano                  uuid        not null references public.plano_producao(id) on delete restrict,

  esta_na_area_2anos        boolean,
  gerente_2anos             boolean,
  herbicida_persiste        boolean,
  daninha                   boolean,
  travamento_soja           boolean,
  soja_anterior             boolean,
  calagem                   boolean,
  revolvimento_solo         boolean,

  cultura_anterior          text,
  ciclo_cultura_anterior    text,
  herbicida_aplicado        text,
  dose_herbicida            numeric(8,3),
  tipo_dosagem_herbicida    text,
  prod_trav_soja            text,
  dosagem_trav_soja         numeric(8,3),
  tipo_dose_trav_soja       text,
  materia_organica          text,
  tipo_de_solo              text,
  ph_solo                   numeric(4,2),
  resultado                 text,

  created_at                timestamptz not null default now(),
  created_by                uuid        not null references public.usuario(id),
  updated_at                timestamptz not null default now(),
  updated_by                uuid,
  revision                  bigint      not null default 1,
  deleted_at                timestamptz,

  -- pH is 0–14 by definition; the legacy decimal(4,2) allowed 99.99.
  constraint checklist_ph_plausivel check (ph_solo is null or ph_solo between 0 and 14),
  constraint checklist_doses_positivas check (
    (dose_herbicida    is null or dose_herbicida    >= 0) and
    (dosagem_trav_soja is null or dosagem_trav_soja >= 0))
);

alter table public.bioensaio_checklist
  add column dosagem_herbicida_dominio text generated always as ('tipo_dosagem_herbicida') stored,
  add column dose_trav_soja_dominio    text generated always as ('tipo_dose_trav_soja')    stored,
  add column tipo_solo_dominio         text generated always as ('tipo_de_solo')           stored,
  add column resultado_dominio         text generated always as ('resultado_checklist')    stored,
  add column cultura_anterior_dominio  text generated always as ('cultura_anterior')       stored;

alter table public.bioensaio_checklist
  add constraint checklist_tipo_dosagem_fk
    foreign key (org_id, dosagem_herbicida_dominio, tipo_dosagem_herbicida)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint checklist_tipo_dose_trav_fk
    foreign key (org_id, dose_trav_soja_dominio, tipo_dose_trav_soja)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint checklist_tipo_solo_fk
    foreign key (org_id, tipo_solo_dominio, tipo_de_solo)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint checklist_resultado_fk
    foreign key (org_id, resultado_dominio, resultado)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint checklist_cultura_anterior_fk
    foreign key (org_id, cultura_anterior_dominio, cultura_anterior)
    references public.parametro(org_id, dominio, codigo) on delete restrict;

-- ---------------------------------------------------------------------------
-- 2. bioensaio — the scored evaluation, hanging off a checklist.
--
-- Three lineages are scored, each with a plant count and a percentage. The
-- percentages are numeric(5,2), not the legacy int: a population percentage
-- rounded to a whole number is a measurement thrown away.
-- ---------------------------------------------------------------------------

create table public.bioensaio (
  id                   uuid        primary key,
  org_id               uuid        not null references public.organizacao(id)        on delete restrict,
  id_checklist         uuid        not null references public.bioensaio_checklist(id) on delete restrict,

  tipo_avaliacao       text,
  data_avaliacao       date,
  linhagem1            integer,
  linhagem2            integer,
  linhagem3            integer,
  pop_l1               integer,
  pop_l2               integer,
  pop_l3               integer,
  percentual_pop_l1    numeric(5,2),
  percentual_pop_l2    numeric(5,2),
  percentual_pop_l3    numeric(5,2),
  status               text,
  observacao           text,

  created_at           timestamptz not null default now(),
  created_by           uuid        not null references public.usuario(id),
  updated_at           timestamptz not null default now(),
  updated_by           uuid,
  revision             bigint      not null default 1,
  deleted_at           timestamptz,

  constraint bioensaio_populacoes_nao_negativas check (
    (pop_l1 is null or pop_l1 >= 0) and
    (pop_l2 is null or pop_l2 >= 0) and
    (pop_l3 is null or pop_l3 >= 0)),
  constraint bioensaio_percentuais_plausiveis check (
    (percentual_pop_l1 is null or percentual_pop_l1 between 0 and 100) and
    (percentual_pop_l2 is null or percentual_pop_l2 between 0 and 100) and
    (percentual_pop_l3 is null or percentual_pop_l3 between 0 and 100))
);

alter table public.bioensaio
  add column tipo_avaliacao_dominio text generated always as ('tipo_avaliacao')   stored,
  add column status_dominio         text generated always as ('status_bioensaio') stored;

alter table public.bioensaio
  add constraint bioensaio_tipo_avaliacao_fk
    foreign key (org_id, tipo_avaliacao_dominio, tipo_avaliacao)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint bioensaio_status_fk
    foreign key (org_id, status_dominio, status)
    references public.parametro(org_id, dominio, codigo) on delete restrict;

-- ---------------------------------------------------------------------------
-- 3. amostra_umidade and its readings.
--
-- THE STRUCTURAL FIX. The legacy TB_UMIDADE held 32 readings as 32 NOT NULL
-- columns, with Media dividing by a hard-coded 32.0 and DesvioPadrao by 31.0.
-- The field team confirmed the reading count VARIES and 32 is only the maximum,
-- which means those NOT NULL columns were forcing invented values and every
-- average computed from fewer than 32 real readings was wrong.
--
-- One row per reading instead. The average and standard deviation come from
-- aggregates over the readings that actually exist (see the view below), so a
-- 20-reading sample is correct without anyone inventing twelve numbers.
--
-- The sample is keyed to id_plano rather than the legacy Hibrido + NumCampo
-- pair, which was a second path to the same parent that nothing kept in step:
-- the plan already determines both.
-- ---------------------------------------------------------------------------

create table public.amostra_umidade (
  id                 uuid        primary key,
  org_id             uuid        not null references public.organizacao(id)    on delete restrict,
  id_plano           uuid        not null references public.plano_producao(id) on delete restrict,
  data_amostra       date        not null,
  dividir_gleba      boolean,
  percentil          numeric(5,2),
  liberado_colheita  boolean,
  observacao         text,

  created_at         timestamptz not null default now(),
  created_by         uuid        not null references public.usuario(id),
  updated_at         timestamptz not null default now(),
  updated_by         uuid,
  revision           bigint      not null default 1,
  deleted_at         timestamptz,

  constraint amostra_percentil_plausivel check (percentil is null or percentil between 0 and 100)
);

comment on table public.amostra_umidade is
  'A moisture sample. Readings live in amostra_umidade_leitura, one row each.';
comment on column public.amostra_umidade.liberado_colheita is
  'Boolean, replacing the legacy nvarchar(3) Sim/Nao.';

create table public.amostra_umidade_leitura (
  id          uuid        primary key,
  org_id      uuid        not null references public.organizacao(id)     on delete restrict,
  id_amostra  uuid        not null references public.amostra_umidade(id) on delete restrict,
  sequencia   smallint    not null,
  valor       numeric(5,2) not null,

  created_at  timestamptz not null default now(),
  created_by  uuid        not null references public.usuario(id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  revision    bigint      not null default 1,
  deleted_at  timestamptz,

  constraint leitura_sequencia_unica  unique (id_amostra, sequencia),
  -- 32 is the protocol maximum, confirmed with the field team.
  constraint leitura_sequencia_valida check (sequencia between 1 and 32),
  constraint leitura_valor_plausivel  check (valor between 0 and 100)
);

-- Media and desvio padrao over the readings that actually exist. stddev_samp
-- is the n-1 divisor the legacy expression used, and returns NULL for a single
-- reading rather than dividing by zero.
--
-- security_invoker = true is NOT optional here. A Postgres view runs with the
-- privileges of its OWNER by default, which would let any caller read every
-- tenant's readings straight through this view while the underlying tables
-- correctly refuse them — the same shape of hole as the SECURITY DEFINER
-- function ADR-013 was written about. With security_invoker the underlying
-- RLS policies apply to the querying user.
create view public.vw_amostra_umidade_resumo
with (security_invoker = true) as
select
  a.id            as id_amostra,
  a.org_id,
  a.id_plano,
  a.data_amostra,
  count(l.id)                        as leituras,
  round(avg(l.valor), 2)             as media,
  round(stddev_samp(l.valor), 2)     as desvio_padrao,
  min(l.valor)                       as minimo,
  max(l.valor)                       as maximo
from public.amostra_umidade a
left join public.amostra_umidade_leitura l
  on l.id_amostra = a.id and l.deleted_at is null
where a.deleted_at is null
group by a.id, a.org_id, a.id_plano, a.data_amostra;

comment on view public.vw_amostra_umidade_resumo is
  'Sample statistics over the readings actually recorded, not a fixed 32.';

-- ---------------------------------------------------------------------------
-- 4. ficha_colheita and carga.
--
-- ficha_colheita is the allocation of a harvest-sheet number to a field. It was
-- NOT selected as técnico-written, so it is server-authoritative: it reaches the
-- device read-only (Class B, ADR-006).
--
-- carga is the load actually recorded against a sheet, and is técnico-written.
-- The legacy model gave DadosColheita and FichaColheita the same composite
-- primary key, making them one-to-one — one load per sheet. That is preserved
-- here as a unique constraint on id_ficha.
--
-- ASSUMPTION worth checking: if a single sheet can carry several loads, drop
-- that unique constraint and carga becomes plain append-only.
-- ---------------------------------------------------------------------------

create table public.ficha_colheita (
  id            uuid        primary key,
  org_id        uuid        not null references public.organizacao(id)    on delete restrict,
  id_plano      uuid        not null references public.plano_producao(id) on delete restrict,
  numero_ficha  text        not null,
  utilizada     boolean     not null default false,

  created_at    timestamptz not null default now(),
  created_by    uuid        not null references public.usuario(id),
  updated_at    timestamptz not null default now(),
  updated_by    uuid,
  revision      bigint      not null default 1,
  deleted_at    timestamptz,

  constraint ficha_numero_unico_por_org unique (org_id, numero_ficha)
);

create table public.carga (
  id                uuid        primary key,
  org_id            uuid        not null references public.organizacao(id)   on delete restrict,
  id_ficha          uuid        not null references public.ficha_colheita(id) on delete restrict,

  tipo_colheita     text,
  fim_enchimento    timestamptz,
  motorista         text,
  placa             text,
  campo_finalizado  boolean     not null default false,
  -- numeric(5,2), NOT the legacy decimal(18,0). Zero decimal places turned a
  -- 12.4% reading into 12, and moisture gates harvest release.
  umidade           numeric(5,2),
  recebimento       text,
  estado_carga      text,
  volume_carga      text,

  created_at        timestamptz not null default now(),
  created_by        uuid        not null references public.usuario(id),
  updated_at        timestamptz not null default now(),
  updated_by        uuid,
  revision          bigint      not null default 1,
  deleted_at        timestamptz,

  constraint carga_uma_por_ficha unique (id_ficha),
  constraint carga_umidade_plausivel check (umidade is null or umidade between 0 and 100)
);

alter table public.carga
  add column tipo_colheita_dominio text generated always as ('tipo_colheita') stored,
  add column recebimento_dominio   text generated always as ('recebimento')   stored,
  add column estado_carga_dominio  text generated always as ('estado_carga')  stored,
  add column volume_carga_dominio  text generated always as ('volume_carga')  stored;

alter table public.carga
  add constraint carga_tipo_colheita_fk
    foreign key (org_id, tipo_colheita_dominio, tipo_colheita)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint carga_recebimento_fk
    foreign key (org_id, recebimento_dominio, recebimento)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint carga_estado_fk
    foreign key (org_id, estado_carga_dominio, estado_carga)
    references public.parametro(org_id, dominio, codigo) on delete restrict,
  add constraint carga_volume_fk
    foreign key (org_id, volume_carga_dominio, volume_carga)
    references public.parametro(org_id, dominio, codigo) on delete restrict;

-- ---------------------------------------------------------------------------
-- 5. alerta_producao — server-authoritative production alert.
--
-- The legacy table had no timestamp at all, so there was no way to tell when an
-- alert was raised. The standard created_at fixes that for free.
--
-- estadio references the same phenological vocabulary as estadio_fenologico
-- rather than repeating it as free text.
-- ---------------------------------------------------------------------------

create table public.alerta_producao (
  id           uuid        primary key,
  org_id       uuid        not null references public.organizacao(id)    on delete restrict,
  id_plano     uuid        not null references public.plano_producao(id) on delete restrict,
  estadio      text,
  tipo_alerta  text        not null,
  observacao   text        not null,
  resolvido_em timestamptz,

  created_at   timestamptz not null default now(),
  created_by   uuid        not null references public.usuario(id),
  updated_at   timestamptz not null default now(),
  updated_by   uuid,
  revision     bigint      not null default 1,
  deleted_at   timestamptz
);

alter table public.alerta_producao
  add column estadio_dominio text generated always as ('estadio_fenologico') stored;

alter table public.alerta_producao
  add constraint alerta_estadio_fk
    foreign key (org_id, estadio_dominio, estadio)
    references public.parametro(org_id, dominio, codigo) on delete restrict;

-- ---------------------------------------------------------------------------
-- 6. Triggers.
-- ---------------------------------------------------------------------------

create trigger trg_bioensaio_checklist_metadata before update on public.bioensaio_checklist
  for each row execute function public.set_row_metadata();
create trigger trg_bioensaio_metadata before update on public.bioensaio
  for each row execute function public.set_row_metadata();
create trigger trg_amostra_umidade_metadata before update on public.amostra_umidade
  for each row execute function public.set_row_metadata();
create trigger trg_leitura_metadata before update on public.amostra_umidade_leitura
  for each row execute function public.set_row_metadata();
create trigger trg_ficha_colheita_metadata before update on public.ficha_colheita
  for each row execute function public.set_row_metadata();
create trigger trg_carga_metadata before update on public.carga
  for each row execute function public.set_row_metadata();
create trigger trg_alerta_metadata before update on public.alerta_producao
  for each row execute function public.set_row_metadata();

-- ---------------------------------------------------------------------------
-- 7. Indexes.
-- ---------------------------------------------------------------------------

create index idx_checklist_org    on public.bioensaio_checklist(org_id)      where deleted_at is null;
create index idx_checklist_plano  on public.bioensaio_checklist(id_plano)    where deleted_at is null;
create index idx_bioensaio_org    on public.bioensaio(org_id)                where deleted_at is null;
create index idx_bioensaio_chk    on public.bioensaio(id_checklist)          where deleted_at is null;
create index idx_amostra_org      on public.amostra_umidade(org_id)          where deleted_at is null;
create index idx_amostra_plano    on public.amostra_umidade(id_plano, data_amostra desc) where deleted_at is null;
create index idx_leitura_org      on public.amostra_umidade_leitura(org_id)  where deleted_at is null;
create index idx_leitura_amostra  on public.amostra_umidade_leitura(id_amostra) where deleted_at is null;
create index idx_ficha_org        on public.ficha_colheita(org_id)           where deleted_at is null;
create index idx_ficha_plano      on public.ficha_colheita(id_plano)         where deleted_at is null;
create index idx_carga_org        on public.carga(org_id)                    where deleted_at is null;
create index idx_carga_ficha      on public.carga(id_ficha)                  where deleted_at is null;
create index idx_alerta_org       on public.alerta_producao(org_id)          where deleted_at is null;
create index idx_alerta_plano     on public.alerta_producao(id_plano)        where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 8. Deny-all floor until the companion policy migration.
-- ---------------------------------------------------------------------------

alter table public.bioensaio_checklist     enable row level security;
alter table public.bioensaio               enable row level security;
alter table public.amostra_umidade         enable row level security;
alter table public.amostra_umidade_leitura enable row level security;
alter table public.ficha_colheita          enable row level security;
alter table public.carga                   enable row level security;
alter table public.alerta_producao         enable row level security;
