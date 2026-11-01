# FieldInfo — Project Instructions

Offline-first Android app for recording field activities in **hybrid corn seed production**
(not commercial grain). Field technicians work for up to 2 days without connectivity.

Read these before starting work:

- @docs/RETOMADA.md — **the project was paused on 2026-11-01.** Where everything lives and how
  to bring it back up. Read it first when resuming
- @docs/DOMAIN.md — what the app is for, entities, the technician's workflow
- @docs/DECISIONS.md — architectural decisions and why (do not silently reverse these)
- @docs/ROADMAP.md — phases, current position, validation criteria
- @docs/ASSESSMENT.md — audit of the original prototype and what was kept

## Stack

| Layer | Choice |
|---|---|
| App | Flutter (Android only for now) |
| Local DB | SQLite, managed by PowerSync |
| Sync engine | PowerSync Cloud |
| Backend | Supabase (Postgres + Auth + Storage) |
| State | Riverpod (see ADR-011) |

## Hard rules — never violate these

1. **The `service_role` key never appears in the app.** Only the `anon` key. Any operation
   requiring elevated privilege goes in a Supabase Edge Function that verifies the caller's
   role server-side.
2. **No widget ever calls Supabase or PowerSync directly.** All data access goes through a
   repository in `lib/data/repositories/`. If you find yourself writing
   `Supabase.instance.client` inside a `build()` or a `State`, stop.
3. **The local database is the source of truth for reads and writes.** The UI never awaits a
   network call to display or save data. Saving means writing to local SQLite; sync happens
   separately and asynchronously.
4. **RLS is enabled on every table, with policies, always.** Authorization lives in Postgres,
   never only in the client. A technician selecting a screen is UX; the database decides
   what they may actually read and write.
5. **Never hard-delete a synced row.** Set `deleted_at`. See ADR-005 on tombstones.
6. **`timestamptz` only.** Never `timestamp without time zone`. Field timestamps must survive
   timezone changes and DST.
7. **Every schema change is a migration file** under `supabase/migrations/`, applied with the
   Supabase CLI. Never edit schema in the dashboard — the original prototype did this and the
   schema was unreproducible.
8. **Primary keys are client-generated UUIDs**, never database sequences. Offline record
   creation depends on this.

## Required columns on every synced table

```
id            uuid primary key            -- generated on the client
org_id        uuid not null               -- tenant scope, drives RLS
created_at    timestamptz not null default now()
created_by    uuid not null references usuarios(id)
updated_at    timestamptz not null default now()
updated_by    uuid
revision      bigint not null default 1   -- incremented by trigger
deleted_at    timestamptz                 -- soft delete; null = live
```

## Conventions

- **Domain nouns stay in Portuguese** (`fazenda`, `gleba`, `safra`, `semeadura`, `hibrido`) —
  they have no clean English equivalents and the users speak Portuguese.
- **Technical identifiers in English** (`repository`, `syncQueue`, `deletedAt`, `orgId`).
- **All user-facing strings in Portuguese**, via `flutter_localizations` + ARB files. Never
  hardcode UI text in widgets.
- Table names singular-ish and snake_case, matching what already exists (`plano_producao`).
- Dart files snake_case; classes PascalCase.
- Format decimals with `intl` for pt-BR (comma separator). Never hand-roll date formatting —
  the prototype did this and it will break.

## Target folder layout

```
lib/
  app/            # entry point, routing, theme, localization
  domain/         # entities + business rules. Zero imports of Flutter, Supabase, PowerSync.
  data/
    local/        # PowerSync schema, queries, migrations
    remote/       # Supabase client, Edge Function calls, upload connector
    repositories/ # the only thing the UI layer is allowed to touch
  sync/           # sync service, connectivity, conflict resolution, attachment queue
  features/       # UI grouped by feature (campos, semeadura, bioensaio, umidade, colheita)
  core/           # errors, logging, result types, shared widgets
```

## How to work on this project

- **Explain before large changes.** If a change touches sync, auth, or the schema, describe
  the approach and wait for confirmation.
- **Small, testable increments.** One concern per change. Never generate many features at once.
- **State assumptions explicitly** rather than guessing at domain rules — ask instead.
- **Always include the migration** when changing the schema, and say how to test the change.
- The developer is a capable beginner. Write readable code and follow best practice, but
  explain any non-obvious pattern in a comment or in the reply. Question his choices when
  you disagree — he wants that.
- When an architectural decision is made in conversation, **append it to `docs/DECISIONS.md`**
  so the next session inherits it.

## Known traps in this project

- PowerSync needs Postgres logical replication. Idle Supabase instances can accumulate
  excessive WAL and fill the disk — check `max_wal_size` / `max_slot_wal_keep_size` config.
- PowerSync does **not** sync files. Photos need a separate attachment queue against
  Supabase Storage, with the local file path stored in SQLite.
- Android background sync is unreliable without a battery-optimization exemption. Devices are
  company-managed, so IT can whitelist the app — the "sync overnight" behaviour depends on it.
- `semeadura` is one row per field, **edited incrementally over weeks**. It is the only
  entity with real conflict risk. Treat it accordingly (ADR-006).
