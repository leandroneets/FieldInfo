# FieldInfo

Offline-first Android app for recording field activities in hybrid corn seed production.
Field technicians work for up to 2 days without connectivity.

> **Project paused on 2026-11-01.** To pick it up again, start with
> [docs/RETOMADA.md](docs/RETOMADA.md) — where everything lives, how to bring it back up, and
> where the work stopped.

See [docs/DOMAIN.md](docs/DOMAIN.md) for what the app does, [docs/ROADMAP.md](docs/ROADMAP.md)
for where the build currently stands, and [CLAUDE.md](CLAUDE.md) for architecture rules.

## Requirements

- Flutter SDK (Android toolchain configured — `flutter doctor` should be clean)
- A Supabase project
- Android device or emulator

## Setup

**1. Install dependencies**

```bash
flutter pub get
```

**2. Configure Supabase credentials**

Copy the template and fill in both values:

```bash
cp assets/.env.example assets/.env
```

Both come from the Supabase dashboard:

| Value | Where to find it |
|---|---|
| `SUPABASE_URL` | Settings → Data API → API URL |
| `SUPABASE_PUBLISHABLE_KEY` | Settings → API Keys → Publishable key (`sb_publishable_…`) |

`SUPABASE_URL` must be the project origin only — `https://<project-ref>.supabase.co`, with no
path and no trailing slash. The dashboard shows it with `/rest/v1/` appended; strip that. The
SDK adds `/auth/v1`, `/rest/v1` and `/storage/v1` itself, so leaving the path in place makes
login fail with a 404 `invalid path specified in request url`.

`assets/.env` is gitignored and must never be committed. The app will not start without it —
`dotenv.load` throws at launch if the file is missing.

**3. Run**

```bash
flutter run
```

## Credentials policy

Only the **publishable** key belongs in this repo's configuration. It is a client-side key: it
ships inside the APK by design, carries the same low privileges as the retired `anon` key, and
Row Level Security decides what any caller may actually read or write.

The **secret** key (`sb_secret_…`) is server-side only. It must never appear in `assets/.env`,
in source, or in the app bundle. Operations needing elevated privilege go in a Supabase Edge
Function that verifies the caller's role server-side.

This is not a hypothetical rule — the original prototype shipped the `service_role` key inside
the APK, which bypassed RLS entirely for anyone who unzipped it. See
[docs/ASSESSMENT.md](docs/ASSESSMENT.md).
