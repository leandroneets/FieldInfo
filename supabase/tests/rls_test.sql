-- Phase 2 validation: authorization is enforced by Postgres, not by the client.
--
-- Run against any database with seed.sql and dev_seed.sql applied:
--   psql "<connection string>" -f supabase/tests/rls_test.sql
--
-- The whole script runs inside a transaction that is ROLLED BACK, including the
-- second tenant it fabricates. Nothing persists. Any failed assertion aborts
-- with an exception, so a clean run ending in ROLLBACK means every check passed.
--
-- Impersonation works by setting `role` to authenticated and planting a `sub`
-- claim, which is what auth.uid() reads. Running as postgres would bypass RLS
-- entirely and prove nothing.

\set ON_ERROR_STOP on

begin;

-- Assertion helper. It lives in pg_temp and takes the condition as a parameter,
-- because psql does not interpolate :variables inside dollar-quoted blocks —
-- the comparison therefore has to happen in the statement, not in the body.
create or replace function pg_temp.assert(cond boolean, msg text)
returns void
language plpgsql
as $fn$
begin
  if cond is not true then
    raise exception 'ASSERTION FAILED: %', msg;
  end if;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Fixtures: a second tenant, so cross-tenant isolation can be tested.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email)
values ('99999999-9999-4999-8999-999999999999', 'tecnico.orgb@example.test');

insert into public.organizacao (id, org_id, nome)
values ('88888888-8888-4888-8888-888888888888',
        '88888888-8888-4888-8888-888888888888',
        'Organizacao B');

insert into public.usuario (id, org_id, nome, email, papel)
values ('99999999-9999-4999-8999-999999999999',
        '88888888-8888-4888-8888-888888888888',
        'Tecnico B', 'tecnico.orgb@example.test', 'tecnico');

-- Identify the org A actors created by seed.sql.
select id as tec_a from public.usuario where papel = 'tecnico'  and org_id = '00000000-0000-4000-8000-000000000001' limit 1 \gset
select id as sup_a from public.usuario where papel = 'suporte'  and org_id = '00000000-0000-4000-8000-000000000001' limit 1 \gset

-- ---------------------------------------------------------------------------
-- 1. Técnico of org A sees ONLY the field assigned to him.
-- ---------------------------------------------------------------------------

select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims', json_build_object('sub', :'tec_a')::text, true);

select count(*) as n from public.plano_producao \gset tecA_

select set_config('role', 'postgres', true);

-- ---------------------------------------------------------------------------
-- 2. Suporte of org A sees the whole organizacao.
-- ---------------------------------------------------------------------------

select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims', json_build_object('sub', :'sup_a')::text, true);

select count(*) as n from public.plano_producao \gset supA_

select set_config('role', 'postgres', true);

-- ---------------------------------------------------------------------------
-- 3. Técnico of org B sees NOTHING belonging to org A. This is the criterion
--    named in the roadmap: authenticate as a técnico of one org, attempt to
--    read another, get zero rows.
-- ---------------------------------------------------------------------------

select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims',
                  json_build_object('sub', '99999999-9999-4999-8999-999999999999')::text, true);

select count(*) as n from public.plano_producao \gset tecB_
select count(*) as n from public.usuario        \gset tecBu_
select count(*) as n from public.material       \gset tecBm_

select set_config('role', 'postgres', true);

-- ---------------------------------------------------------------------------
-- 4. A técnico cannot grant himself an assignment.
--
--    The prototype left usuario_plano open and writable, which made every
--    other policy decorative (docs/ASSESSMENT.md).
-- ---------------------------------------------------------------------------

select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims', json_build_object('sub', :'tec_a')::text, true);

do $$
begin
  begin
    insert into public.usuario_plano (id, org_id, id_usuario, id_plano, created_by)
    values (gen_random_uuid(),
            '00000000-0000-4000-8000-000000000001',
            (select (current_setting('request.jwt.claims')::json ->> 'sub')::uuid),
            'eeeeeeee-0000-4000-8000-000000000002',
            (select (current_setting('request.jwt.claims')::json ->> 'sub')::uuid));
    raise exception 'ASSERTION FAILED: tecnico was able to self-assign a field';
  exception
    when insufficient_privilege then null;  -- expected: RLS refused the insert
  end;
end $$;

select set_config('role', 'postgres', true);

-- ---------------------------------------------------------------------------
-- 5. The ADR-006 edit lock: once a semeadura reaches a status carrying
--    bloqueia_edicao, the técnico can no longer edit it.
-- ---------------------------------------------------------------------------

insert into public.semeadura (id, org_id, id_plano, status_semeadura, observacao, created_by)
values ('77777777-7777-4777-8777-777777777777',
        '00000000-0000-4000-8000-000000000001',
        'eeeeeeee-0000-4000-8000-000000000001',
        'Plantando', 'inicial', :'sup_a');

select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims', json_build_object('sub', :'tec_a')::text, true);

-- Unlocked: the assigned técnico may edit, and may close the record himself.
update public.semeadura set observacao = 'editado pelo tecnico'
where id = '77777777-7777-4777-8777-777777777777';

select count(*) as n from public.semeadura
where id = '77777777-7777-4777-8777-777777777777' and observacao = 'editado pelo tecnico' \gset edit_

update public.semeadura set status_semeadura = 'Finalizado'
where id = '77777777-7777-4777-8777-777777777777';

-- Locked: further técnico edits must affect zero rows.
update public.semeadura set observacao = 'nao deveria passar'
where id = '77777777-7777-4777-8777-777777777777';

select count(*) as n from public.semeadura
where id = '77777777-7777-4777-8777-777777777777' and observacao = 'nao deveria passar' \gset locked_

select set_config('role', 'postgres', true);

-- ---------------------------------------------------------------------------
-- 6. Class A append-only: a técnico may record an observation but not rewrite
--    one. Silently editable measurements defeat the point of an audit trail.
-- ---------------------------------------------------------------------------

select set_config('role', 'authenticated', true),
       set_config('request.jwt.claims', json_build_object('sub', :'tec_a')::text, true);

insert into public.estadio_fenologico
  (id, org_id, id_semeadura, estadio, data_apontamento, observacao, created_by)
values ('66666666-6666-4666-8666-666666666666',
        '00000000-0000-4000-8000-000000000001',
        '77777777-7777-4777-8777-777777777777',
        'V3', current_date, 'original', :'tec_a');

select count(*) as n from public.estadio_fenologico
where id = '66666666-6666-4666-8666-666666666666' \gset estIns_

update public.estadio_fenologico set observacao = 'reescrito'
where id = '66666666-6666-4666-8666-666666666666';

select count(*) as n from public.estadio_fenologico
where id = '66666666-6666-4666-8666-666666666666' and observacao = 'reescrito' \gset estUpd_

-- ---------------------------------------------------------------------------
-- 7. The moisture fix: the average must come from the readings that exist.
--
--    Three readings of 10, 12 and 14 average to 12.00. The legacy expression
--    divided by a hard-coded 32.0 and would have produced 1.13 — which is what
--    every sample of fewer than 32 readings was silently recording.
-- ---------------------------------------------------------------------------

insert into public.amostra_umidade (id, org_id, id_plano, data_amostra, created_by)
values ('55550000-5555-4555-8555-555500000001',
        '00000000-0000-4000-8000-000000000001',
        'eeeeeeee-0000-4000-8000-000000000001', current_date, :'tec_a');

insert into public.amostra_umidade_leitura (id, org_id, id_amostra, sequencia, valor, created_by)
values (gen_random_uuid(), '00000000-0000-4000-8000-000000000001', '55550000-5555-4555-8555-555500000001', 1, 10.00, :'tec_a'),
       (gen_random_uuid(), '00000000-0000-4000-8000-000000000001', '55550000-5555-4555-8555-555500000001', 2, 12.00, :'tec_a'),
       (gen_random_uuid(), '00000000-0000-4000-8000-000000000001', '55550000-5555-4555-8555-555500000001', 3, 14.00, :'tec_a');

select leituras as n from public.vw_amostra_umidade_resumo
where id_amostra = '55550000-5555-4555-8555-555500000001' \gset umidN_

select media as n from public.vw_amostra_umidade_resumo
where id_amostra = '55550000-5555-4555-8555-555500000001' \gset umidMedia_

select desvio_padrao as n from public.vw_amostra_umidade_resumo
where id_amostra = '55550000-5555-4555-8555-555500000001' \gset umidSd_

select set_config('role', 'postgres', true);

-- ---------------------------------------------------------------------------
-- Assertions.
-- ---------------------------------------------------------------------------

select pg_temp.assert(:tecA_n   = 1, 'tecnico A must see exactly 1 plan (only the assigned one)');
select pg_temp.assert(:supA_n   = 2, 'suporte A must see both plans in the organizacao');
select pg_temp.assert(:tecB_n   = 0, 'CROSS-TENANT LEAK: tecnico B saw org A plans');
select pg_temp.assert(:tecBu_n  = 1, 'tecnico B must see only his own org usuarios');
select pg_temp.assert(:tecBm_n  = 0, 'CROSS-TENANT LEAK: tecnico B saw org A materials');
select pg_temp.assert(:edit_n   = 1, 'assigned tecnico must be able to edit an unlocked semeadura');
select pg_temp.assert(:locked_n = 0, 'EDIT LOCK BROKEN: tecnico edited a Finalizado semeadura');
select pg_temp.assert(:estIns_n  = 1, 'tecnico must be able to record a phenological observation');
select pg_temp.assert(:estUpd_n  = 0, 'APPEND-ONLY BROKEN: tecnico rewrote an existing observation');
select pg_temp.assert(:umidN_n   = 3, 'moisture sample must report 3 readings');
select pg_temp.assert(:umidMedia_n = 12.00, 'moisture average must be 12.00 over 3 readings, not divided by a fixed 32');
select pg_temp.assert(:umidSd_n  = 2.00, 'moisture standard deviation must be 2.00 (n-1 over the real readings)');

do $$ begin raise notice 'ALL RLS ASSERTIONS PASSED'; end $$;

rollback;
