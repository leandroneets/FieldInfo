-- Phase 2b — policies for the Phase 1d activity tables.
--
-- Same shape as 20260827021042: visibility follows the plan assignment, writes
-- follow the conflict class from ADR-006.
--
--   Class A (append-only): the assigned técnico may INSERT freely but not
--   UPDATE or DELETE. Correcting an observation is an admin action, because
--   silently rewriting a measurement destroys the audit trail these records
--   exist to provide.
--
--   Class B (server-authoritative): ficha_colheita and alerta_producao are
--   SELECT-only for everyone except suporte. The técnico reads them; the app
--   never writes them.

-- Convenience: may the caller see this plan at all?
create or replace function public.pode_ver_plano(p_plano uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select public.is_admin() or public.tem_atribuicao(p_plano)
$fn$;

revoke execute on function public.pode_ver_plano(uuid) from public, anon;
grant  execute on function public.pode_ver_plano(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- bioensaio_checklist — Class A.
-- ---------------------------------------------------------------------------

create policy checklist_select on public.bioensaio_checklist
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy checklist_insert on public.bioensaio_checklist
  for insert to authenticated
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy checklist_admin_update on public.bioensaio_checklist
  for update to authenticated
  using      (org_id = public.current_org_id() and public.is_admin())
  with check (org_id = public.current_org_id() and public.is_admin());

create policy checklist_delete on public.bioensaio_checklist
  for delete to authenticated
  using (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- bioensaio — Class A, reached through its checklist.
-- ---------------------------------------------------------------------------

create policy bioensaio_select on public.bioensaio
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and exists (select 1 from public.bioensaio_checklist c
                where c.id = id_checklist and public.pode_ver_plano(c.id_plano)));

create policy bioensaio_insert on public.bioensaio
  for insert to authenticated
  with check (
    org_id = public.current_org_id()
    and exists (select 1 from public.bioensaio_checklist c
                where c.id = id_checklist and public.pode_ver_plano(c.id_plano)));

create policy bioensaio_admin_update on public.bioensaio
  for update to authenticated
  using      (org_id = public.current_org_id() and public.is_admin())
  with check (org_id = public.current_org_id() and public.is_admin());

create policy bioensaio_delete on public.bioensaio
  for delete to authenticated
  using (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- amostra_umidade and its readings — Class A.
--
-- Readings are insertable by the assigned técnico while the sample is being
-- taken, and immutable afterwards for anyone below admin. A moisture reading
-- that can be quietly edited is not a measurement.
-- ---------------------------------------------------------------------------

create policy amostra_select on public.amostra_umidade
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy amostra_insert on public.amostra_umidade
  for insert to authenticated
  with check (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy amostra_admin_update on public.amostra_umidade
  for update to authenticated
  using      (org_id = public.current_org_id() and public.is_admin())
  with check (org_id = public.current_org_id() and public.is_admin());

create policy amostra_delete on public.amostra_umidade
  for delete to authenticated
  using (org_id = public.current_org_id() and public.is_suporte());

create policy leitura_select on public.amostra_umidade_leitura
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and exists (select 1 from public.amostra_umidade a
                where a.id = id_amostra and public.pode_ver_plano(a.id_plano)));

create policy leitura_insert on public.amostra_umidade_leitura
  for insert to authenticated
  with check (
    org_id = public.current_org_id()
    and exists (select 1 from public.amostra_umidade a
                where a.id = id_amostra and public.pode_ver_plano(a.id_plano)));

create policy leitura_admin_update on public.amostra_umidade_leitura
  for update to authenticated
  using      (org_id = public.current_org_id() and public.is_admin())
  with check (org_id = public.current_org_id() and public.is_admin());

create policy leitura_delete on public.amostra_umidade_leitura
  for delete to authenticated
  using (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- ficha_colheita — Class B, server-authoritative.
--
-- Sheet numbers are allocated by the office. A técnico who could mint his own
-- would break the reconciliation the sheet exists for.
-- ---------------------------------------------------------------------------

create policy ficha_select on public.ficha_colheita
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy ficha_write on public.ficha_colheita
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- carga — técnico-written, reached through its ficha.
--
-- Updatable by the assigned técnico while campo_finalizado is false. Once the
-- load is closed it follows the same amendment rule as a locked semeadura.
-- ---------------------------------------------------------------------------

create policy carga_select on public.carga
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and exists (select 1 from public.ficha_colheita f
                where f.id = id_ficha and public.pode_ver_plano(f.id_plano)));

create policy carga_insert on public.carga
  for insert to authenticated
  with check (
    org_id = public.current_org_id()
    and exists (select 1 from public.ficha_colheita f
                where f.id = id_ficha and public.pode_ver_plano(f.id_plano)));

create policy carga_update on public.carga
  for update to authenticated
  using (
    org_id = public.current_org_id()
    and (public.is_admin()
         or (not campo_finalizado
             and exists (select 1 from public.ficha_colheita f
                         where f.id = id_ficha and public.tem_atribuicao(f.id_plano)))))
  with check (
    org_id = public.current_org_id()
    and exists (select 1 from public.ficha_colheita f
                where f.id = id_ficha and public.pode_ver_plano(f.id_plano)));

create policy carga_delete on public.carga
  for delete to authenticated
  using (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- alerta_producao — Class B, server-authoritative.
--
-- The técnico reads alerts raised for his fields and never writes them. Marking
-- one resolved is an admin action for now; if the field team wants técnicos to
-- acknowledge alerts, that becomes a narrow UPDATE policy on resolvido_em only.
-- ---------------------------------------------------------------------------

create policy alerta_select on public.alerta_producao
  for select to authenticated
  using (org_id = public.current_org_id() and public.pode_ver_plano(id_plano));

create policy alerta_write on public.alerta_producao
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_admin())
  with check (org_id = public.current_org_id() and public.is_admin());
