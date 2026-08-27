-- The Postgres role PowerSync connects as.
--
-- ---------------------------------------------------------------------------
-- WHY THIS ROLE HOLDS BYPASSRLS, AND WHAT THAT MEANS
--
-- PowerSync reads the write-ahead log for every row in the publication and
-- decides who receives what by applying Sync Rules itself. It therefore has to
-- see all tenants' rows during replication, which is what BYPASSRLS grants.
--
-- The consequence is worth stating plainly, because it inverts the usual
-- assumption: for data flowing DOWN to a device, Sync Rules are the only
-- boundary. Row-level security does not filter replication. A mistake in
-- sync_rules.yaml is a cross-tenant leak that no policy will catch.
--
-- RLS still governs everything else — uploads, which travel back through
-- PostgREST as the authenticated user, and any direct API read. Both layers
-- matter; they simply guard different directions.
--
-- REPLICATION is required to consume the logical slot. No write privilege is
-- granted: PowerSync never writes to this database. Uploads go through
-- PostgREST under the user's own credentials, where policies apply.
--
-- ---------------------------------------------------------------------------
-- PASSWORD — deliberately not set here
--
-- The role is created able to log in but without a password, so it cannot
-- authenticate until you set one. A credential in a committed migration is the
-- Phase 0 mistake repeated, and this one would be a BYPASSRLS credential.
--
-- Generate a strong password and set it directly, never through a migration:
--
--   alter role powersync_role with password '<generated>';
--
-- Then give that password to PowerSync's connection dialog. It belongs in the
-- PowerSync dashboard and your password manager — nowhere else, and not in
-- this repository.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'powersync_role') then
    create role powersync_role with replication bypassrls login;
  end if;
end
$$;

-- Read-only across the public schema. ALTER DEFAULT PRIVILEGES covers tables
-- created by future migrations, so a new table is replicable without anyone
-- remembering to grant on it — a table PowerSync cannot read fails at
-- replication time, which is a confusing way to discover a missing grant.
grant usage on schema public to powersync_role;
grant select on all tables in schema public to powersync_role;
alter default privileges in schema public grant select on tables to powersync_role;

comment on role powersync_role is
  'Replication role for PowerSync. BYPASSRLS by necessity; read-only.';
