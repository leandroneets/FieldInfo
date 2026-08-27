# Roadmap

Progress marker — update as phases complete.

**Current phase: 3**

---

## Phase 0 — Security and hygiene

**Objective:** Close the leaked-credential hole and make the repo reproducible.

- [x] Migrate to publishable/secret API keys and **deactivate the legacy keys** — this is what
      actually revoked the leaked `service_role` key. Supabase no longer supports rotating the
      legacy `anon`/`service_role`/JWT secrets in place, so "rotate" was not an option.
      Done 2026-08-09; only the publishable key is in `assets/.env`, login verified against it.
- [ ] Migrate to JWT signing keys (ES256) — the project still uses the original shared JWT
      secret. Migration and rotation are zero-downtime and sign nobody out; only revoking the
      legacy key before existing access tokens expire would force logouts.
- [x] Remove `auth.admin.createUser` from `create_user.dart` (the screen stays, the call goes)
- [x] Install Supabase CLI (2.113.0, via Scoop); `supabase init`; project linked.
      The prototype schema was **not** made migration 0000 — it is archived as
      `docs/schema_snapshot.sql` instead, since Phase 1 replaces it wholesale. Migration
      history therefore starts at the RLS baseline below. Captured with `pg_dump`
      (also Scoop-installed) rather than `supabase db dump`, which requires Docker.
- [x] Enable RLS on all existing tables with deny-all policies as a baseline —
      migration `20260809052924_baseline_rls_deny_all.sql`. Also closed an RLS bypass:
      `semeadura_changes_since()` is SECURITY DEFINER and was executable by PUBLIC,
      returning any technician's `semeadura` rows to anyone holding the publishable key.
      Verified after push: 6/6 tables RLS-on with 0 policies, function reachable only by
      `postgres` and `service_role`.
- [x] Delete `usuarios.senha` column — migration `20260809055618_drop_usuarios_senha.sql`
      written and verified null in all rows; awaiting `supabase db push`
- [x] Delete `tmp_view.txt`
- [x] Set a real `applicationId` — `br.com.fieldinfo.app`, in both `applicationId` and
      `namespace`, with `MainActivity.kt` moved to the matching Kotlin package. Permanent once
      published to the Play Store. Non-Android bundle IDs still read `com.example` and are
      deliberately untouched (ADR-010: Android only).
- [x] Add `assets/.env.example` and document setup in README
- [ ] **Change the database password before the field pilot.** The current value was exposed in
      a chat transcript on 2026-08-09 and is the Postgres superuser credential. Acceptable while
      the database holds 7 test rows; not acceptable once real field data lands in it.

**Output:** a repo any developer can clone and build, with no secret in it.
**Validation:** grep the built APK for the `service_role` key — zero hits. App still logs in.
**Dependencies:** none. Nothing else starts until this is done.

---

## Phase 1 — Domain model and schema

**Objective:** The complete Postgres schema, designed for offline sync and multi-tenancy.

- [x] Entities, keys, FKs, constraints — migrations `phase1a` … `phase1d`. Status enums are
      **not** CHECK constraints: superseded by ADR-014, which puts admin-managed vocabulary in
      `parametro` with a composite FK. `usuario.papel` stays a CHECK, deliberately.
- [x] Standard sync columns on every table (see CLAUDE.md)
- [x] `organizacao` as tenant root
- [x] `revision` / `updated_at` triggers — `set_row_metadata()`
- [ ] **Audit table and triggers — still outstanding.** Nothing records who changed what beyond
      `updated_by` / `revision` on the row itself. Needed before the field pilot.
- [x] Unique constraints — including `usuario_plano(id_usuario, id_plano)` and
      `semeadura(id_plano)`, which enforces one planting record per field
- [x] Migration files, applied via CLI

**Output:** `supabase/migrations/`, and an ER diagram in `docs/SCHEMA.md` *(diagram not written)*.
**Validation:** migrations apply to an empty database from scratch, twice, cleanly —
**not yet satisfiable.** `20260809052924` references tables it does not create (ADR-012).
Resolving this means a squashed baseline migration; it has not been done.
**Dependencies:** Phase 0.

---

## Phase 2 — RLS and permissions

**Objective:** Authorization enforced in Postgres.

- [x] Security-definer helpers — `current_org_id()`, `current_papel()` (named for the domain,
      not `current_role()`, which collides with a Postgres built-in), plus `is_admin()`,
      `is_suporte()`, `tem_atribuicao()`, `pode_ver_plano()`, `semeadura_bloqueada()`.
      All revoked from PUBLIC and granted only to `authenticated`.
- [x] Per-table, per-role, per-operation policies — `phase2` and `phase2b`
- [x] Technicians read only their assigned fields, and write only their own activity records.
      Class A tables are append-only for técnicos: INSERT yes, UPDATE admin-only.
- [x] Master data read-only for técnicos, writable by suporte
- [x] SQL test script — `supabase/tests/rls_test.sql`, 13 assertions in a rolled-back
      transaction, including the ADR-006 edit lock and the moisture-average correctness check

**Output:** policy migrations + a test script.
**Validation:** authenticate as a técnico of org A and attempt to read org B — must return
nothing. **Passing:** the script fabricates a second tenant and asserts 0 rows visible.
**Dependencies:** Phase 1.

---

## Phase 3 — Local database and PowerSync

**Objective:** The app reads from local SQLite, populated by PowerSync.

- [ ] PowerSync instance connected to Supabase; publication configured
- [ ] `max_wal_size` / `max_slot_wal_keep_size` configured (see CLAUDE.md traps)
- [ ] PowerSync client schema mirroring the Postgres schema
- [ ] Sync Rules: technician receives only his assigned fields; supervisor receives his org
- [ ] Upload connector writing back through PostgREST
- [ ] `SyncStatusService` exposing state to the UI

**Output:** app displays real data with the network fully disabled.
**Validation:** airplane mode, cold start — field list still renders.
**Dependencies:** Phase 2.

---

## Phase 4 — Repositories and domain layer

**Objective:** One and only one path to data.

- [ ] Domain entities with no Flutter/Supabase/PowerSync imports
- [ ] Repository per aggregate, exposing reactive streams from local SQLite
- [ ] `Result` type for error handling; no exceptions crossing into the UI
- [ ] Validation rules in the domain layer, mirroring the DB constraints

**Output:** `lib/domain/`, `lib/data/repositories/`.
**Validation:** unit tests against an in-memory database; zero `Supabase.instance` references
outside `lib/data/remote/`.
**Dependencies:** Phase 3.

---

## Phase 5 — Authentication, offline sessions, permissions

**Objective:** Login survives days offline.

- [ ] Supabase Auth with refresh tokens in `flutter_secure_storage`
- [ ] Offline unlock (cached session + local PIN or biometric) with a defined max offline window
- [ ] Expired-session handling that never discards pending local data
- [ ] Role resolution cached locally
- [ ] Edge Function for user creation, role-checked server-side

**Output:** `lib/features/auth/`, `supabase/functions/create-user/`.
**Validation:** log in, enable airplane mode, force-stop the app, reopen 48h later (clock
shifted) — still usable, pending data intact.
**Dependencies:** Phase 4.

---

## Phase 6 — Core field workflow

**Objective:** The logbook the technician actually uses.

- [ ] "Meus Campos" home screen with per-field activity timeline
- [ ] Semeadura create/edit, ported from the prototype form
- [ ] `anotacao_campo` field-book entries with GPS
- [ ] Draft autosave — a partially filled form is never lost
- [ ] Pending/synced/conflict indicator per record
- [ ] pt-BR localization and number/date formatting via `intl`

**Output:** `lib/features/campos/`, `lib/features/semeadura/`, `lib/features/anotacoes/`.
**Validation:** complete a full semeadura entry offline, kill the app mid-form, reopen — draft
recovered; sync on reconnect.
**Dependencies:** Phase 5.

---

## Phase 7 — Photos and attachments

**Objective:** Photos captured offline, uploaded reliably later.

- [ ] Capture, compress, store on local disk with the path in SQLite
- [ ] Attachment queue against Supabase Storage, resumable
- [ ] Storage RLS scoped by `org_id`
- [ ] Local cleanup after confirmed upload; disk-space guard

**Output:** `lib/sync/attachments/`.
**Validation:** 20 photos captured offline; upload interrupted mid-file; resumes and completes
with no duplicates and no orphaned rows.
**Dependencies:** Phase 6.

---

## Phase 8 — Conflict resolution

**Objective:** Class C conflicts surfaced and resolvable, never silently lost.

- [ ] Conflict detection on `revision` mismatch during upload
- [ ] Field-level merge for draft-state records
- [ ] Lock enforcement on completed/approved records
- [ ] Supervisor resolution screen showing both versions side by side
- [ ] Technician notification when their submission needs attention

**Output:** `lib/sync/conflicts/`, `lib/features/conflitos/`.
**Validation:** the two-device scenarios in `docs/SYNC.md`, all passing.
**Dependencies:** Phase 7.

---

## Phase 9 — Remaining activities

**Objective:** Bioensaio, estádio fenológico, colheita, cargas, umidade.

All are Class A append-only except colheita, so they reuse Phase 6 patterns with little new risk.
Deliberately sequenced last — the architecture is proven by then.

**Dependencies:** Phase 8.

---

## Phase 10 — Testing, monitoring, release

- [ ] Integration tests for every scenario in `docs/SYNC.md`
- [ ] Schema migration applied while pending offline records exist
- [ ] Simulated multi-day offline accumulation
- [ ] Crash and error reporting (Sentry or equivalent), with sync failures reported
- [ ] Play Store internal testing track; battery-optimization exemption with IT
- [ ] Field pilot with one technician for one real week before wider rollout

**Validation:** the full test matrix in `docs/TESTING.md` passes on a physical device.
