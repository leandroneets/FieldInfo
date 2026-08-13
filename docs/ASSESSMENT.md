# Prototype Assessment (July 2026)

Audit of the original FieldInfo prototype, kept so the reasoning behind ADR-001 isn't lost.

> **Revised 2026-08-09** against a `pg_dump` of the live database
> (`docs/schema_snapshot.sql`). The original audit was written without reading the schema
> directly and got two findings wrong — one withdrawn, one understated. Corrections are marked
> inline. Findings closed since the audit are marked in the table.

## What it was

1,504 lines of Dart across 10 files, one git commit, everything in `lib/screens/`. No model
layer, no repository layer, no local database, no sync code. All 14 database calls sat directly
inside widget `State` classes; every row was a `Map<String, dynamic>`. Postgres schema built by
hand in the dashboard, no migrations, database empty and never used in production.

`provider`, `connectivity_plus`, `flutter_secure_storage` and `crypto` were declared in
`pubspec.yaml` and imported by zero files — offline support was an intention, not code.

## The failure mode that motivated the rebuild

A technician with no signal opened the semeadura form. `_loadPlanosAtribuidos()` threw, the
field dropdown came back empty, and he could not begin the form. With signal at open but not at
save, `_save()` threw, showed a snackbar, and everything typed was lost on `Navigator.pop`.

## Findings

| Where | Problem | Severity |
|---|---|---|
| `create_user.dart` | `auth.admin.createUser` called from Flutter — the `service_role` key was in the app bundle, bypassing all RLS for anyone who unzipped the APK | CRITICAL |
| `usuarios.senha` | Plaintext password column alongside Supabase Auth | CRITICAL |
| Schema-wide | RLS on only 2 of 6 tables (`plano_producao`, `semeadura`); `usuarios`, `usuario_plano`, `material`, `safra` fully open to the publishable key. `usuario_plano` was also *writable*, letting anyone grant themselves a field assignment | CRITICAL |
| `semeadura_changes_since()` | SECURITY DEFINER, executable by PUBLIC, returned up to 2000 `semeadura` rows with no authorization check — an RLS bypass reachable via PostgREST by anyone holding the publishable key | CRITICAL |
| `semeadura` RLS policy | Matched `usuario_plano.id_usuario = auth.uid()`, which can never be true since `usuarios.id_usuario` is an unrelated `gen_random_uuid()`. Verified: 0 of 2 rows matched. The policy denied everyone | HIGH |
| `role_router.dart` | Role chose which screen rendered; nothing enforced server-side | HIGH |
| `usuarios` | Keyed by mutable email, no FK to `auth.users.id`; RLS couldn't reach `auth.uid()` | HIGH |
| Whole `lib/` | No local persistence | HIGH |
| ~~`usuario_plano`~~ | ~~No `UNIQUE(id_usuario, id_plano)`~~ — **incorrect, withdrawn 2026-08-09.** The constraint `usuario_plano_id_usuario_id_plano_key` does exist; the code's `23505` guard works as intended | — |
| Schema-wide | Only `semeadura` had `revision`/`updated_at`/`deleted_at` | HIGH |
| `criado_em` | `timestamp without time zone`, while `semeadura.updated_at` was `timestamptz` | HIGH |
| `plano_producao` | Farm, field, sector, hectares, season and hybrid collapsed into one row; `num_campo` not unique | MEDIUM |
| Schema | No tenant table | MEDIUM |
| `semeadura.id_plano` | Nullable — orphan planting records possible | MEDIUM |
| `status_semeadura`, `tipoespacamento` | Free text; allowed values lived only in Dart | MEDIUM |
| `build.gradle.kts` | `applicationId = com.example.fieldinfo` | MEDIUM |
| `main.dart`, `create_user.dart` | `BuildContext` used across `await` with no `mounted` check | LOW |
| `tmp_view.txt` | Stale duplicate of `home_tecnico.dart` with mojibake | LOW |

## Carried forward

- The Flutter project and Android configuration.
- **All screen layouts as UI reference.** The animated FAB menu in `home_tecnico.dart` is good
  work and its interaction design should survive the rebuild.
- The `semeadura` field list — the most accurate available specification of what the domain
  needs to record.
- The three-role concept.
- The Supabase project itself (keys rotated).
