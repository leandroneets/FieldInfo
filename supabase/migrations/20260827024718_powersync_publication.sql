-- Logical replication publication for PowerSync.
--
-- PowerSync replicates by consuming a Postgres logical replication slot fed by
-- this publication. Tables absent from it are invisible to sync regardless of
-- what the Sync Rules say.
--
-- Named tables rather than FOR ALL TABLES: a blanket publication would also
-- replicate anything added later by accident, and there is no reason to stream
-- rows nobody syncs.
--
-- ---------------------------------------------------------------------------
-- REPLICA IDENTITY
--
-- Left at DEFAULT, which uses the primary key. Every table here has a single
-- uuid primary key that is never updated (ADR-009 — keys are client-generated
-- and immutable), so DEFAULT carries everything PowerSync needs to identify a
-- changed or deleted row. FULL would replicate every column's old value on each
-- update, multiplying WAL volume for no benefit here.
--
-- ---------------------------------------------------------------------------
-- ⚠ THE WAL TRAP — read this before pausing anything
--
-- A logical replication slot retains WAL until its consumer acknowledges it. If
-- PowerSync stops consuming — instance paused, project paused, credentials
-- rotated, sync rules rejected — Postgres keeps every WAL segment since the last
-- acknowledged position, and the database disk fills. This is the failure mode
-- named in CLAUDE.md, and on a small Supabase instance it can take the database
-- down entirely.
--
-- The guard is `max_slot_wal_keep_size`, which caps retention and invalidates
-- the slot instead of exhausting the disk. An invalidated slot means PowerSync
-- must resync from scratch — recoverable, unlike a full disk.
--
-- It cannot be set here: it is a server-level setting, ALTER SYSTEM is not
-- transactional, and `supabase db push` runs migrations in a transaction. Set it
-- separately, once:
--
--   supabase --experimental postgres-config update --config max_slot_wal_keep_size=2GB
--
-- or in the dashboard under Settings -> Database -> Custom Postgres config.
-- Verify with:  show max_slot_wal_keep_size;   (-1 means unlimited = unguarded)
-- ---------------------------------------------------------------------------

drop publication if exists powersync;

create publication powersync for table
  -- Tenant and identity
  public.organizacao,
  public.usuario,
  -- Master data / reference
  public.safra,
  public.material,
  public.fazenda,
  public.gleba,
  public.parametro,
  -- Planning and assignment
  public.plano_producao,
  public.usuario_plano,
  -- Field activities
  public.semeadura,
  public.semeadura_basica,
  public.estadio_fenologico,
  public.bioensaio_checklist,
  public.bioensaio,
  public.amostra_umidade,
  public.amostra_umidade_leitura,
  public.ficha_colheita,
  public.carga,
  public.alerta_producao;

-- vw_amostra_umidade_resumo is intentionally absent: it is a view, computed
-- from amostra_umidade_leitura, which does sync. The client recomputes the
-- average locally from the readings it already holds rather than syncing a
-- derived value that could disagree with them.
