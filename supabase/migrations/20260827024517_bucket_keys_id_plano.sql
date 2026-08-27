-- Denormalise id_plano onto every activity table, as a PowerSync bucket key.
--
-- WHY THIS IS NECESSARY
--
-- PowerSync Sync Rules cannot join. Each data query filters exactly one table
-- against a bucket parameter, so a table can only reach a device if the column
-- the bucket is keyed on lives on that table itself.
--
-- Five tables currently reach their field only through a parent:
--
--   semeadura_basica        -> semeadura
--   estadio_fenologico      -> semeadura
--   bioensaio               -> bioensaio_checklist
--   amostra_umidade_leitura -> amostra_umidade
--   carga                   -> ficha_colheita
--
-- Without id_plano on each of them, they cannot be synced per-assignment at
-- all; the alternative is shipping every technician the whole organizacao,
-- which defeats the point of Sync Rules and contradicts docs/DOMAIN.md.
--
-- WHY THIS IS NOT THE DRIFT PROBLEM I OBJECTED TO IN 1c
--
-- The legacy model carried both id_plano and NumCampo on SEMEADURA with two
-- independent foreign keys and nothing forcing them to agree — a row could
-- point at two different fields.
--
-- Here the denormalised column is constrained rather than merely present. Each
-- parent gains a UNIQUE (id, id_plano) — redundant on its own, since id is
-- already unique, but it gives a composite foreign key something to reference.
-- The child then carries (parent_id, id_plano) and a composite FK into it, so
-- Postgres rejects any row whose id_plano disagrees with its parent's. The
-- value is copied, but it cannot diverge.
--
-- Backfill is a no-op today: these tables are empty. The UPDATE statements are
-- written anyway so the migration is correct if applied to a populated
-- database, and the columns are only set NOT NULL afterwards.

-- ---------------------------------------------------------------------------
-- 1. Parents gain the composite unique key their children will reference.
-- ---------------------------------------------------------------------------

alter table public.semeadura
  add constraint semeadura_id_plano_key unique (id, id_plano);

alter table public.bioensaio_checklist
  add constraint checklist_id_plano_key unique (id, id_plano);

alter table public.amostra_umidade
  add constraint amostra_id_plano_key unique (id, id_plano);

alter table public.ficha_colheita
  add constraint ficha_id_plano_key unique (id, id_plano);

-- ---------------------------------------------------------------------------
-- 2. semeadura_basica
-- ---------------------------------------------------------------------------

alter table public.semeadura_basica add column id_plano uuid;

update public.semeadura_basica c
   set id_plano = s.id_plano
  from public.semeadura s
 where s.id = c.id_semeadura;

alter table public.semeadura_basica
  alter column id_plano set not null,
  add constraint semeadura_basica_plano_coerente
    foreign key (id_semeadura, id_plano)
    references public.semeadura (id, id_plano) on delete restrict;

-- ---------------------------------------------------------------------------
-- 3. estadio_fenologico
-- ---------------------------------------------------------------------------

alter table public.estadio_fenologico add column id_plano uuid;

update public.estadio_fenologico c
   set id_plano = s.id_plano
  from public.semeadura s
 where s.id = c.id_semeadura;

alter table public.estadio_fenologico
  alter column id_plano set not null,
  add constraint estadio_plano_coerente
    foreign key (id_semeadura, id_plano)
    references public.semeadura (id, id_plano) on delete restrict;

-- ---------------------------------------------------------------------------
-- 4. bioensaio
-- ---------------------------------------------------------------------------

alter table public.bioensaio add column id_plano uuid;

update public.bioensaio b
   set id_plano = c.id_plano
  from public.bioensaio_checklist c
 where c.id = b.id_checklist;

alter table public.bioensaio
  alter column id_plano set not null,
  add constraint bioensaio_plano_coerente
    foreign key (id_checklist, id_plano)
    references public.bioensaio_checklist (id, id_plano) on delete restrict;

-- ---------------------------------------------------------------------------
-- 5. amostra_umidade_leitura
-- ---------------------------------------------------------------------------

alter table public.amostra_umidade_leitura add column id_plano uuid;

update public.amostra_umidade_leitura l
   set id_plano = a.id_plano
  from public.amostra_umidade a
 where a.id = l.id_amostra;

alter table public.amostra_umidade_leitura
  alter column id_plano set not null,
  add constraint leitura_plano_coerente
    foreign key (id_amostra, id_plano)
    references public.amostra_umidade (id, id_plano) on delete restrict;

-- ---------------------------------------------------------------------------
-- 6. carga
-- ---------------------------------------------------------------------------

alter table public.carga add column id_plano uuid;

update public.carga g
   set id_plano = f.id_plano
  from public.ficha_colheita f
 where f.id = g.id_ficha;

alter table public.carga
  alter column id_plano set not null,
  add constraint carga_plano_coerente
    foreign key (id_ficha, id_plano)
    references public.ficha_colheita (id, id_plano) on delete restrict;

-- ---------------------------------------------------------------------------
-- 7. Indexes on the new bucket keys.
--
-- Every Sync Rules data query filters on id_plano, so these are on the hot path
-- for replication, not just for the app.
-- ---------------------------------------------------------------------------

create index idx_semeadura_basica_plano on public.semeadura_basica(id_plano)        where deleted_at is null;
create index idx_estadio_plano          on public.estadio_fenologico(id_plano)      where deleted_at is null;
create index idx_bioensaio_plano        on public.bioensaio(id_plano)               where deleted_at is null;
create index idx_leitura_plano          on public.amostra_umidade_leitura(id_plano) where deleted_at is null;
create index idx_carga_plano            on public.carga(id_plano)                   where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 8. Policies can now check the assignment directly instead of walking to the
--    parent, which also means RLS and Sync Rules express the same rule the same
--    way — the pair least likely to drift apart.
-- ---------------------------------------------------------------------------

drop policy if exists semeadura_basica_select on public.semeadura_basica;
drop policy if exists semeadura_basica_write  on public.semeadura_basica;

create policy semeadura_basica_select on public.semeadura_basica
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy semeadura_basica_write on public.semeadura_basica
  for all to authenticated
  using (
    org_id = public.current_org_id()
    and (public.is_admin()
         or (public.tem_atribuicao(id_plano)
             and not public.semeadura_bloqueada(id_semeadura))))
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

drop policy if exists estadio_select on public.estadio_fenologico;
drop policy if exists estadio_insert on public.estadio_fenologico;

create policy estadio_select on public.estadio_fenologico
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy estadio_insert on public.estadio_fenologico
  for insert to authenticated
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

drop policy if exists bioensaio_select on public.bioensaio;
drop policy if exists bioensaio_insert on public.bioensaio;

create policy bioensaio_select on public.bioensaio
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy bioensaio_insert on public.bioensaio
  for insert to authenticated
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

drop policy if exists leitura_select on public.amostra_umidade_leitura;
drop policy if exists leitura_insert on public.amostra_umidade_leitura;

create policy leitura_select on public.amostra_umidade_leitura
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy leitura_insert on public.amostra_umidade_leitura
  for insert to authenticated
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

drop policy if exists carga_select on public.carga;
drop policy if exists carga_insert on public.carga;
drop policy if exists carga_update on public.carga;

create policy carga_select on public.carga
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy carga_insert on public.carga
  for insert to authenticated
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy carga_update on public.carga
  for update to authenticated
  using (
    org_id = public.current_org_id()
    and (public.is_admin()
         or (not campo_finalizado and public.tem_atribuicao(id_plano))))
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));
