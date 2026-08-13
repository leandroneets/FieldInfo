-- Baseline security posture for the prototype schema.
--
-- Purpose: every table denies by default, and no function hands out a way
-- around that. Real per-role policies arrive in Phase 2; this migration only
-- establishes the floor they will be built on.
--
-- Why "deny-all" needs no policies: once RLS is enabled on a table, a table
-- with zero policies denies every row to every ordinary role. `service_role`
-- and the table owner (`postgres`) hold BYPASSRLS and are unaffected, so Edge
-- Functions and the dashboard keep working.
--
-- Idempotent: safe to run twice. `enable row level security` is a no-op when
-- already enabled, `drop policy if exists` tolerates a missing policy, and
-- `revoke` on a privilege that is already absent succeeds silently.

-- ---------------------------------------------------------------------------
-- 1. Tables that had no row-level security at all.
--
-- `usuarios` exposed every name, email and role to anyone holding the
-- publishable key, which ships inside the APK by design. `usuario_plano` was
-- worse: it was writable, and it is the table the `plano_producao` policy
-- consults to decide who may see which field — so anyone could grant
-- themselves an assignment.
-- ---------------------------------------------------------------------------

alter table public.usuarios      enable row level security;
alter table public.usuario_plano enable row level security;
alter table public.material      enable row level security;
alter table public.safra         enable row level security;

-- ---------------------------------------------------------------------------
-- 2. Tables that had RLS on, but with policies we are deliberately retiring.
--
-- The two existing policies resolved identity in two different and mutually
-- inconsistent ways:
--
--   * `plano_producao` matched on `usuarios.email = auth.email()`. It worked,
--     but keys authorization to a mutable column — the exact problem ADR-008
--     exists to prevent.
--
--   * `semeadura` matched on `usuario_plano.id_usuario = auth.uid()`. This one
--     never evaluated true: `usuarios.id_usuario` is an independent
--     `gen_random_uuid()` with no relationship to `auth.users.id`. Verified
--     against the live database — 0 of 2 rows matched.
--
-- Dropping both leaves all six tables at the same honest baseline rather than
-- preserving one policy that works by accident and one that never worked.
-- Phase 2 rebuilds these on `auth.uid()` once `usuarios.id` is keyed to
-- `auth.users.id`.
-- ---------------------------------------------------------------------------

drop policy if exists "Technicians see only assigned fields" on public.plano_producao;
drop policy if exists semeadura_rw on public.semeadura;

-- Re-assert RLS on both. Already enabled today, but stated explicitly so this
-- migration fully describes the end state rather than depending on prior state.
alter table public.plano_producao enable row level security;
alter table public.semeadura      enable row level security;

-- ---------------------------------------------------------------------------
-- 3. Close the RLS bypass.
--
-- `semeadura_changes_since` is SECURITY DEFINER and owned by `postgres`, so it
-- executes with RLS bypassed and returns up to 2000 rows with no authorization
-- check of its own. PostgREST publishes it at
-- `/rest/v1/rpc/semeadura_changes_since`, making it reachable by anyone with
-- the publishable key.
--
-- Revoking from PUBLIC is the part that actually matters: the grant was
-- `=X/postgres`, which is PUBLIC holding EXECUTE. Revoking from `anon` and
-- `authenticated` alone would leave them executing through PUBLIC anyway. They
-- are named as well so the intent survives a future re-GRANT to PUBLIC.
--
-- The function is a hand-rolled incremental-sync mechanism that PowerSync
-- replaces (ADR-002). It should be dropped outright in Phase 1; this migration
-- only removes reachability, which is the reversible half.
-- ---------------------------------------------------------------------------

revoke execute on function public.semeadura_changes_since(timestamptz)
  from public, anon, authenticated;
