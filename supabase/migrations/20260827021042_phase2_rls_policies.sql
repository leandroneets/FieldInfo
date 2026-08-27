-- Phase 2 — authorization enforced in Postgres.
--
-- Replaces the deny-all floor from 20260809052924 with real per-role,
-- per-operation policies. Until now every table denied everything; this is the
-- migration that makes the application able to read its own data.
--
-- ---------------------------------------------------------------------------
-- WHY THE HELPERS ARE SECURITY DEFINER
--
-- A policy on `usuario` that calls a helper which selects from `usuario` would
-- re-enter the same policy and recurse until Postgres aborts. SECURITY DEFINER
-- makes the helper run as its owner, bypassing RLS for that lookup only. This
-- is the standard resolution and the reason these four functions exist at all.
--
-- ADR-013 was written because the prototype shipped a SECURITY DEFINER function
-- executable by PUBLIC that leaked every semeadura row. These are narrower by
-- construction — each returns only a fact about the *calling* user, derived
-- from auth.uid(), and none takes a parameter that could widen its scope. They
-- are still explicitly revoked from PUBLIC and granted only to `authenticated`.
--
-- ---------------------------------------------------------------------------
-- WHY POLICIES DO NOT FILTER deleted_at
--
-- Soft-deleted rows stay visible to the policies. ADR-005 requires a deletion
-- to propagate and never resurrect; hiding tombstones at the RLS layer would
-- make a delete indistinguishable from "never existed" for a client that still
-- holds the old row. The application filters `deleted_at is null` for display.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Helpers.
-- ---------------------------------------------------------------------------

create or replace function public.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $fn$
  select u.org_id
  from public.usuario u
  where u.id = (select auth.uid())
    and u.deleted_at is null
    and u.ativo
$fn$;

create or replace function public.current_papel()
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select u.papel
  from public.usuario u
  where u.id = (select auth.uid())
    and u.deleted_at is null
    and u.ativo
$fn$;

-- Supervisor and suporte both see the whole organizacao; técnico does not.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(public.current_papel() in ('supervisor', 'suporte'), false)
$fn$;

create or replace function public.is_suporte()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(public.current_papel() = 'suporte', false)
$fn$;

-- Is the calling user assigned to this production plan?
create or replace function public.tem_atribuicao(p_plano uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.usuario_plano up
    where up.id_plano = p_plano
      and up.id_usuario = (select auth.uid())
      and up.deleted_at is null
  )
$fn$;

-- ADR-006: a semeadura whose status carries bloqueia_edicao is closed to the
-- técnico. The lock keys off the flag, never off the label, so renaming
-- 'Finalizado' cannot silently disable it.
create or replace function public.semeadura_bloqueada(p_semeadura uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.semeadura s
    join public.parametro pa
      on  pa.org_id  = s.org_id
      and pa.dominio = 'status_semeadura'
      and pa.codigo  = s.status_semeadura
    where s.id = p_semeadura
      and pa.bloqueia_edicao
  )
$fn$;

revoke execute on function
  public.current_org_id(), public.current_papel(), public.is_admin(),
  public.is_suporte(), public.tem_atribuicao(uuid), public.semeadura_bloqueada(uuid)
from public, anon;

grant execute on function
  public.current_org_id(), public.current_papel(), public.is_admin(),
  public.is_suporte(), public.tem_atribuicao(uuid), public.semeadura_bloqueada(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- 2. organizacao — you may see your own tenant, and nobody writes it from the
--    app. Creating an organizacao is a Phase 5 Edge Function concern.
-- ---------------------------------------------------------------------------

create policy organizacao_select on public.organizacao
  for select to authenticated
  using (id = public.current_org_id());

-- ---------------------------------------------------------------------------
-- 3. usuario — everyone in the tenant can see their colleagues (the app shows
--    who recorded what). Only suporte writes.
-- ---------------------------------------------------------------------------

create policy usuario_select on public.usuario
  for select to authenticated
  using (org_id = public.current_org_id());

create policy usuario_write on public.usuario
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- 4. Master data — readable by the whole tenant, writable only by suporte.
--
-- Readability matters more than it looks: docs/DOMAIN.md requires every
-- reference dropdown to work offline, so safra, material and parametro must
-- reach a técnico's device even though he never edits them.
-- ---------------------------------------------------------------------------

create policy safra_select on public.safra
  for select to authenticated using (org_id = public.current_org_id());
create policy safra_write on public.safra
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

create policy material_select on public.material
  for select to authenticated using (org_id = public.current_org_id());
create policy material_write on public.material
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

create policy fazenda_select on public.fazenda
  for select to authenticated using (org_id = public.current_org_id());
create policy fazenda_write on public.fazenda
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

create policy gleba_select on public.gleba
  for select to authenticated using (org_id = public.current_org_id());
create policy gleba_write on public.gleba
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

create policy parametro_select on public.parametro
  for select to authenticated using (org_id = public.current_org_id());
create policy parametro_write on public.parametro
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- 5. plano_producao — the core visibility rule.
--
-- A técnico sees only the fields assigned to him; supervisor and suporte see
-- the whole organizacao. This is the rule PowerSync Sync Rules will mirror in
-- Phase 3, and it is what makes "Meus Campos" a plain select in the client.
-- ---------------------------------------------------------------------------

create policy plano_select on public.plano_producao
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and (public.is_admin() or public.tem_atribuicao(id))
  );

create policy plano_write on public.plano_producao
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- 6. usuario_plano — a técnico may see his own assignments, never grant them.
--
-- The prototype left this table open and writable, which let anyone assign
-- themselves any field (docs/ASSESSMENT.md). Only suporte writes here.
-- ---------------------------------------------------------------------------

create policy usuario_plano_select on public.usuario_plano
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and (public.is_admin() or id_usuario = (select auth.uid()))
  );

create policy usuario_plano_write on public.usuario_plano
  for all to authenticated
  using      (org_id = public.current_org_id() and public.is_suporte())
  with check (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- 7. semeadura — Class C. Read by the assigned técnico, written by him only
--    while the record is unlocked.
--
-- The UPDATE policy's USING clause is evaluated against the row as it exists
-- before the change, so a record already at a bloqueia_edicao status refuses
-- further técnico edits. Setting the status TO 'Finalizado' is still allowed —
-- that is the técnico closing his own record. Reopening it requires a
-- supervisor, which is exactly the ADR-006 amendment rule.
-- ---------------------------------------------------------------------------

create policy semeadura_select on public.semeadura
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and (public.is_admin() or public.tem_atribuicao(id_plano))
  );

create policy semeadura_insert on public.semeadura
  for insert to authenticated
  with check (
    org_id = public.current_org_id()
    and (public.is_admin() or public.tem_atribuicao(id_plano))
  );

create policy semeadura_update on public.semeadura
  for update to authenticated
  using (
    org_id = public.current_org_id()
    and (
      public.is_admin()
      or (public.tem_atribuicao(id_plano) and not public.semeadura_bloqueada(id))
    )
  )
  with check (
    org_id = public.current_org_id()
    and (public.is_admin() or public.tem_atribuicao(id_plano))
  );

create policy semeadura_delete on public.semeadura
  for delete to authenticated
  using (org_id = public.current_org_id() and public.is_suporte());

-- ---------------------------------------------------------------------------
-- 8. semeadura_basica and estadio_fenologico — reached through the parent.
--
-- estadio_fenologico is Class A append-only: insert freely, but a técnico may
-- not rewrite history. Only an admin can update or delete an observation.
-- ---------------------------------------------------------------------------

create policy semeadura_basica_select on public.semeadura_basica
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and exists (
      select 1 from public.semeadura s
      where s.id = id_semeadura
        and (public.is_admin() or public.tem_atribuicao(s.id_plano))
    )
  );

create policy semeadura_basica_write on public.semeadura_basica
  for all to authenticated
  using (
    org_id = public.current_org_id()
    and exists (
      select 1 from public.semeadura s
      where s.id = id_semeadura
        and (public.is_admin()
             or (public.tem_atribuicao(s.id_plano) and not public.semeadura_bloqueada(s.id)))
    )
  )
  with check (
    org_id = public.current_org_id()
    and exists (
      select 1 from public.semeadura s
      where s.id = id_semeadura
        and (public.is_admin() or public.tem_atribuicao(s.id_plano))
    )
  );

create policy estadio_select on public.estadio_fenologico
  for select to authenticated
  using (
    org_id = public.current_org_id()
    and exists (
      select 1 from public.semeadura s
      where s.id = id_semeadura
        and (public.is_admin() or public.tem_atribuicao(s.id_plano))
    )
  );

create policy estadio_insert on public.estadio_fenologico
  for insert to authenticated
  with check (
    org_id = public.current_org_id()
    and exists (
      select 1 from public.semeadura s
      where s.id = id_semeadura
        and (public.is_admin() or public.tem_atribuicao(s.id_plano))
    )
  );

-- Append-only for técnicos: correcting an observation is an admin action.
create policy estadio_admin_write on public.estadio_fenologico
  for update to authenticated
  using      (org_id = public.current_org_id() and public.is_admin())
  with check (org_id = public.current_org_id() and public.is_admin());

create policy estadio_delete on public.estadio_fenologico
  for delete to authenticated
  using (org_id = public.current_org_id() and public.is_suporte());
