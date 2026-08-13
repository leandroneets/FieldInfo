# Domain — FieldInfo

## What this is

Hybrid corn **seed** production, not commercial grain. This matters: the `macho` / `femea`
columns are male and female parent lines, planted in separate windows so that pollen shed and
silking coincide ("nick"). Timing errors destroy the seed lot, so planting dates, spacings and
planting ratio are high-value data, not paperwork.

## Roles

| Role | Does |
|---|---|
| **Técnico** | Works in the field, offline. Records activities against the fields assigned to him. |
| **Supervisor** | Reviews and approves across the organization. Resolves sync conflicts. |
| **Suporte** | Manages master data (safras, materiais, planos) and user accounts. |

Multi-tenant: several companies will use the system. `org_id` scopes everything.

## The technician's actual day

This is the workflow the app must serve. It is a **logbook**, not a set of forms.

1. He *should* open the app the night before to pre-download his data. **He won't.**
   Therefore sync must happen silently in the background: on app foreground, on connectivity
   regained, and on a periodic Android background task. The design must not depend on the
   technician remembering to sync.
2. He arrives at the field, opens the app, and **first looks at what he recorded previously**.
   This is the home screen: his assigned fields, each showing its recent activity.
3. He opens the relevant activity for what he is doing today — semeadura today, bioensaio a few
   weeks later, umidade later still — enters the data, and closes the app.
4. He returns every few days or weeks. Low volume per visit, long-lived records, sustained over
   a whole season.

**Design consequences:**

- Home screen is "Meus Campos" → a field → a timeline of activity → add today's entry.
  Never a blank welcome screen.
- Every screen must open and function with zero connectivity, including the field list and all
  reference dropdowns (safras, materiais, status values).
- Only fields assigned to the technician sync to his device. PowerSync Sync Rules enforce this.

## Entities

**Master data — server-authoritative, download only on technician devices:**
organizacao, usuario, safra, material (hibrido), fazenda, gleba/campo, maquina, unidade de
beneficiamento (destination plant).

**Planning:** plano_producao (links a field to a safra and a material), usuario_plano
(assignment of technicians to plans).

**Field activities — created and edited by technicians:**

| Entity | Cardinality per field | Nature |
|---|---|---|
| semeadura | **one** | Long-lived, edited incrementally over weeks |
| estadio_fenologico | many | Append-only observation |
| bioensaio + checklist | many | Append-only observation |
| colheita | one or few | Long-lived, has a completion/approval state |
| carga (load) | many | Append-only transaction |
| amostra_umidade | many | Append-only measurement |
| anotacao_campo | many | Append-only field-book note |
| anexo (photo/attachment) | many | Immutable once uploaded |

## The field book

The developer asked whether observations should be text columns or a dedicated table.
**Dedicated table: `anotacao_campo`.** A free-text `observacoes` column on every table is
unsearchable, can't hold a photo, and can't be timestamped or geolocated independently of the
parent record. `anotacao_campo` is append-only, timestamped, GPS-tagged, optionally attached to
a specific activity, and can carry photos. It is also the easiest thing in the system to sync,
because append-only data cannot conflict.

## Conflict classes

Three classes fall directly out of the table above. Only one is hard.

**Class A — Append-only** (amostra_umidade, carga, anotacao_campo, bioensaio,
estadio_fenologico, anexo). Every valid record is preserved. Two devices creating records
concurrently is not a conflict — both are facts that happened. Client-generated UUIDs make
inserts naturally idempotent, so retries cannot duplicate. **Never last-write-wins; never
overwrite.**

**Class B — Server-authoritative** (all master data, plano_producao, usuario_plano). The
server always wins; technician devices never write these. Local changes are impossible by
design, so there is nothing to resolve.

**Class C — Mutable operational records** (semeadura, colheita). The genuinely hard case.
Rules:

- While `status` is a draft state: field-level merge on `revision`. A device pushing a change
  based on a stale revision has its non-overlapping fields merged and its overlapping fields
  flagged.
- Once `status` is completed or approved: the record is locked. Further changes require a
  supervisor, and are recorded as an amendment with audit trail rather than an overwrite.
- Where two devices changed the *same field* to different values: **manual resolution**, surfaced
  to the supervisor. Never silently discard a technician's work — the data is too expensive to
  re-collect and losing it destroys trust in the app.

**Deletions:** soft only. A tombstone with `deleted_at` always beats a concurrent edit, and
never resurrects on a later sync.

## Open questions

- Bioassay (bioensaio) checklist structure — what are the actual items scored?
- Phenological stages — fixed scale (V/R stages) or free text?
- Does harvest need per-load moisture, or is moisture sampled independently of loads?
- Who approves a completed semeadura, and can a technician reopen it?
- Retention: how long must a closed safra stay on the device?
