-- Remove the plaintext password column.
--
-- `usuarios.senha` sat alongside Supabase Auth as a second, unmanaged credential
-- store. Supabase Auth is the only credential store (ADR-008); no application
-- code reads or writes this column, and it is null in every existing row, so
-- dropping it loses nothing.
--
-- Verified before writing this migration: `select count(senha) from usuarios`
-- returned 0 across 2 rows.
--
-- `if exists` keeps the migration idempotent, per the Phase 1 requirement that
-- migrations apply cleanly twice.

alter table public.usuarios
  drop column if exists senha;
