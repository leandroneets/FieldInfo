-- Development sample data. NOT bootstrap — supabase/seed.sql is that.
--
-- Run as postgres, after seed.sql:
--   psql "<connection string>" -f supabase/dev_seed.sql
--
-- Creates two production plans and assigns only ONE of them to the técnico.
-- That asymmetry is the point: logged in as the técnico the app must show one
-- field, and as suporte it must show two. If the técnico sees both, the RLS
-- policy is not doing its job.
--
-- Idempotent — fixed UUIDs plus ON CONFLICT DO NOTHING.

\set org      '00000000-0000-4000-8000-000000000001'
\set fazenda  'aaaaaaaa-0000-4000-8000-000000000001'
\set gleba    'bbbbbbbb-0000-4000-8000-000000000001'
\set safra    'cccccccc-0000-4000-8000-000000000001'
\set material 'dddddddd-0000-4000-8000-000000000001'
\set plano1   'eeeeeeee-0000-4000-8000-000000000001'
\set plano2   'eeeeeeee-0000-4000-8000-000000000002'
\set atrib    'ffffffff-0000-4000-8000-000000000001'

-- Author every row as the suporte user.
create temporary view autor as
  select id from public.usuario where papel = 'suporte' order by created_at limit 1;

insert into public.fazenda (id, org_id, nome, cooperado, created_by)
select :'fazenda', :'org', 'Fazenda Santa Helena', 'Cooperativa Vale Verde', a.id from autor a
on conflict (id) do nothing;

insert into public.gleba (id, org_id, id_fazenda, nome, created_by)
select :'gleba', :'org', :'fazenda', 'Gleba Norte', a.id from autor a
on conflict (id) do nothing;

insert into public.safra (id, org_id, codigo, data_inicio, data_fim, created_by)
select :'safra', :'org', '2026/2027', date '2026-09-01', date '2027-08-31', a.id from autor a
on conflict (id) do nothing;

insert into public.material (id, org_id, hibrido, macho, femea, cultura, umidade_min, umidade_max, created_by)
select :'material', :'org', 'AG-1051', 'LM-77', 'LF-42', 'Milho', 12.00, 14.50, a.id from autor a
on conflict (id) do nothing;

-- Field 101 — assigned to the técnico.
insert into public.plano_producao
  (id, org_id, id_safra, id_material, id_gleba, num_campo, hectare, setor, modo_colheita, created_by)
select :'plano1', :'org', :'safra', :'material', :'gleba', 101, 48.50, 'Setor A', 'Espiga', a.id from autor a
on conflict (id) do nothing;

-- Field 102 — deliberately NOT assigned. The técnico must not see this one.
insert into public.plano_producao
  (id, org_id, id_safra, id_material, id_gleba, num_campo, hectare, setor, modo_colheita, created_by)
select :'plano2', :'org', :'safra', :'material', :'gleba', 102, 33.20, 'Setor B', 'AXF', a.id from autor a
on conflict (id) do nothing;

insert into public.usuario_plano (id, org_id, id_usuario, id_plano, created_by)
select :'atrib', :'org', t.id, :'plano1', a.id
from autor a, (select id from public.usuario where papel = 'tecnico' order by created_at limit 1) t
on conflict (id) do nothing;

drop view autor;
