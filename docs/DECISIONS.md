# Architectural Decisions

Append new decisions here. Do not reverse an existing one without recording a superseding entry.

---

## ADR-001 — Rebuild the foundation, keep Flutter and the UI work

**Status:** Accepted

The prototype was 1,504 lines of Dart with no model layer, no repository layer, no local
database and no sync code — all 14 database calls sat inside widget `State`. The Postgres
database was empty and had never been used in production.

Rebuilding the data layer therefore costs almost nothing, because there wasn't one, and there
is zero data to migrate. Retrofitting offline support onto direct `Supabase.instance` calls
inside `setState` would cost more than replacing them, and would risk a half-migrated state
where some screens work offline and some don't — the worst possible outcome for field trust.

**Kept:** the Flutter project and Android config, every screen layout as UI reference (the FAB
menu in `home_tecnico.dart` in particular), the `semeadura` field list as a domain spec, the
role concept, the Supabase project.

**Rejected:** a full from-scratch restart. Flutter is the right choice for one Android target
with a small team, and discarding working UI would gain nothing.

---

## ADR-002 — PowerSync as the sync engine

**Status:** Accepted

Alternative considered: Drift + a hand-written outbox sync engine (~600–900 lines).

The dominant risk to this project is not cost or lock-in — it is a subtle sync bug causing a
technician to lose a day of field data. That happens once and the field team stops trusting the
app permanently. Interrupted uploads, restart recovery, ordering and duplicate prevention are
the hard parts, and PowerSync solves them. Effort goes instead into the conflict *rules*, which
are domain decisions nobody else can make for us.

Lock-in is bounded: data always lives in our own Supabase Postgres, and a free self-hosted Open
Edition exists if cost or dependency becomes a problem. Free tier (2 GB synced/month, 50
concurrent connections) is far above this project's needs.

**Accepted costs:** a second service in the stack; Postgres logical replication with its WAL
growth caveat; photos not covered and needing a separate attachment queue.

**Reversibility:** repositories sit *above* the sync engine, so the domain model and UI are
unaffected if this is ever revisited.

---

## ADR-003 — Multi-tenant from day one

**Status:** Accepted

Multiple companies will use the system. `org_id` goes on every table now and anchors all RLS
policies. Retrofitting a tenant column after data exists is a painful migration; adding an
unused column to an empty database is free.

---

## ADR-004 — Local SQLite is the source of truth

**Status:** Accepted

Reads and writes both go to local SQLite. Saving a record means committing locally; the UI
returns immediately and never awaits the network. Sync is a separate background concern.

This is the whole point of the project. In the prototype, a technician with no signal could not
even populate the field dropdown, and anything typed into a form was lost on save failure.

---

## ADR-005 — Soft deletion with tombstones

**Status:** Accepted

No synced row is ever hard-deleted. `deleted_at` marks deletion. A tombstone always wins over a
concurrent edit, and a deleted record must never reappear after a later sync from a device that
still held the old row. Purging happens server-side only, well after all devices have synced.

---

## ADR-006 — Conflict rules by data class, not one global rule

**Status:** Accepted

Three classes — append-only, server-authoritative, and mutable operational records. Detailed in
@docs/DOMAIN.md. Last-write-wins is explicitly rejected as a blanket policy: it is correct for
nothing here and silently destroys measurement data.

---

## ADR-007 — No privileged operations in the client

**Status:** Accepted

The prototype called `auth.admin.createUser` from Flutter, which requires the `service_role`
key. That key was therefore inside the app bundle, granting anyone who unzipped the APK full
RLS-bypassing access to the entire database.

The key has been rotated. Only the `anon` key ships in the app. User creation and any other
privileged operation moves to a Supabase Edge Function that verifies the caller's role
server-side. Role-based screen routing is UX only and is never treated as authorization.

---

## ADR-008 — Identity keyed to `auth.users.id`

**Status:** Accepted

The prototype's `usuarios` table had its own `id_usuario` and was looked up by email. Email is
mutable, and RLS policies cannot cleanly reach it. `usuarios.id` now equals `auth.users.id`
with a foreign key, so policies can use `auth.uid()` directly. Role is resolved through a
security-definer function rather than a client-side query.

Also removed: the plaintext `usuarios.senha` column. Supabase Auth is the only credential store.

---

## ADR-009 — Client-generated UUID primary keys

**Status:** Accepted

UUIDv4, generated on the device via the `uuid` package. Offline record creation requires it, and
it makes inserts naturally idempotent — a retried upload cannot create a duplicate. Database
sequences are impossible offline. (UUIDv7 would give better index locality; revisit only if
insert volume ever justifies the complexity.)

---

## ADR-010 — Android only, for now

**Status:** Accepted

Company-managed Android devices. iOS is not a target, which simplifies background sync,
permissions and testing. Flutter keeps the option open at low cost.

Consequence: IT must grant the app a battery-optimization exemption, or Android Doze and OEM
process killers will prevent the background sync that the "he won't sync the night before"
assumption depends on.

---

## ADR-011 — Riverpod for state management

**Status:** Accepted

The prototype declared `provider` but never imported it; 41 `setState` calls managed everything
locally. Riverpod is chosen over Provider and BLoC because PowerSync exposes reactive queries as
streams, and Riverpod's `StreamProvider` maps onto that directly with very little ceremony —
which suits both the architecture and a developer who wants readable code.

---

## ADR-012 — Migration history starts at the security baseline, not the prototype schema

**Status:** Accepted (supersedes the Phase 0 roadmap item "capture current schema as migration
0000")

The original plan was to capture the existing Postgres schema as migration 0000 and evolve from
there. Rejected after reading the actual schema (`docs/schema_snapshot.sql`, `pg_dump` of
2026-08-09).

Phase 1 replaces that schema in full: there is no tenant table, `usuarios` is keyed by a
standalone UUID unrelated to `auth.users.id`, status columns are free text, and the standard
sync columns exist only on `semeadura`. Blessing it as 0000 would mean every future rebuild of
the database constructs the flawed schema and then mutates it into the correct one, forever —
including creating `usuarios.senha` only to drop it in the next migration.

The prototype schema is instead archived as `docs/schema_snapshot.sql`. This preserves
everything ADR-001 and `docs/ASSESSMENT.md` actually need it for — provenance and the record of
what was audited — without binding future migrations to it.

**Accepted cost:** migrations do not currently apply to an empty database from scratch, because
`20260809052924_baseline_rls_deny_all.sql` references tables it does not create. Phase 1 must
resolve this by supplying the schema that precedes it, and Phase 1's validation criterion
("migrations apply to an empty database from scratch, twice, cleanly") is not satisfiable until
it does.

---

## ADR-013 — Authorization is rebuilt from a deny-all floor, not patched

**Status:** Accepted

The prototype had RLS on 2 of 6 tables. The two policies resolved identity in mutually
inconsistent ways: `plano_producao` matched `usuarios.email = auth.email()` (functional, but
keyed to a mutable column — the problem ADR-008 exists to prevent), while `semeadura` matched
`usuario_plano.id_usuario = auth.uid()` and could never evaluate true, because
`usuarios.id_usuario` is an independent `gen_random_uuid()`. Verified against live data: 0 of 2
rows matched.

Both were dropped rather than kept and extended. A baseline where every table denies uniformly
is worth more than one policy that works by accident alongside one that never worked, and Phase
2 rebuilds both on `auth.uid()` once `usuarios.id` is keyed to `auth.users.id`.

Also closed in the same migration: `semeadura_changes_since()`, a SECURITY DEFINER function
executable by PUBLIC that returned up to 2000 `semeadura` rows with no authorization check,
reachable via PostgREST by anyone holding the publishable key. It is a hand-rolled incremental
sync that PowerSync supersedes (ADR-002) and should be dropped outright in Phase 1; the
migration only revoked reachability, which is the reversible half.

**Consequence:** the prototype's técnico screens return zero rows until Phase 2. Accepted —
those screens are UI reference being rebuilt, not production functionality.
