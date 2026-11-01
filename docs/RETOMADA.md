# Retomada — como voltar a mexer neste projeto

**Projeto pausado em 2026-11-01.** O último trabalho é de 2026-09-05. Este arquivo diz onde está
cada coisa, como pôr o app de pé de novo, e onde o trabalho parou. O resto está em:

| Documento | Responde |
|---|---|
| `CLAUDE.md` | stack, regras duras, convenções e armadilhas |
| `docs/DOMAIN.md` | o que o app faz: entidades e o fluxo do técnico |
| `docs/DECISIONS.md` | ADR-001 a ADR-014 |
| `docs/ROADMAP.md` | fases 0 a 10, com critério de validação de cada uma |
| `docs/ASSESSMENT.md` | a auditoria do protótipo original e o que foi mantido |

---

## 1. Onde está cada coisa

| O quê | Onde | Observação |
|---|---|---|
| Código e histórico | GitHub, `leandroneets/FieldInfo` — **público** | branch `main` = último estado |
| Cópia completa da pasta | `Projetos-arquivados-2026-11-01.zip` | inclui `assets/.env` (URL + chave publicável), que não está no GitHub |
| Banco | Supabase, projeto `heeqxhwfjcycobljagir` (Postgres 17), schema `public` | **não é** o projeto do Plant Management. Só dados de teste. **Não foi feito dump**: o `.env` deste app só tem a chave publicável, sem senha de Postgres |
| Sync | PowerSync Cloud, uma instância apontando para esse projeto | a senha do `powersync_role` existe só no painel do PowerSync |
| Memória do Claude Code | não havia memória própria deste projeto | — |

### Ação recomendada ao pausar: desligar o PowerSync

O PowerSync replica pelo WAL do Postgres através de um *replication slot*. **Um slot ativo num
banco parado segura WAL até encher o disco** (está nas armadilhas do `CLAUDE.md`), e o
`max_slot_wal_keep_size` nunca foi confirmado como aplicado. Enquanto o projeto estiver parado:

1. No painel do PowerSync, **pause ou apague a instância**.
2. No Supabase (SQL editor), confira se sobrou slot e apague:
   `select slot_name, active from pg_replication_slots;` e, se houver um inativo do PowerSync,
   `select pg_drop_replication_slot('<nome>');`

Na volta, a instância é recriada no painel e o slot nasce de novo sozinho.

O Supabase gratuito também **pausa o projeto** depois de uns dias sem uso, e um projeto pausado
por muito tempo pode deixar de ser restaurável. Como o schema inteiro está em
`supabase/migrations/` e os dados são de teste, perder o projeto custa só recriá-lo.

---

## 2. Pôr de pé de novo

### Pré-requisitos

- **Flutter** com toolchain Android (`flutter doctor` limpo). Última versão usada: Flutter 3.44.8,
  Dart 3.12.2. O `pubspec.yaml` pede Dart `^3.7.2`.
- **Supabase CLI** (2.113.0 na época, instalado pelo Scoop) e **pg_dump/psql** (Scoop,
  `postgresql`). O `supabase db dump` exige Docker, por isso o projeto usa `pg_dump` direto.
- Um aparelho ou emulador Android. O app é só Android (ADR-010); o `applicationId` é
  `br.com.fieldinfo.app` e é permanente depois de publicado.

### Passo a passo

```bash
git clone https://github.com/leandroneets/FieldInfo.git
cd FieldInfo
flutter pub get
cp assets/.env.example assets/.env   # ou copie o assets/.env do zip
flutter run
```

O `assets/.env` precisa de `SUPABASE_URL` (só a origem, sem `/rest/v1/`),
`SUPABASE_PUBLISHABLE_KEY` (`sb_publishable_…`) e `POWERSYNC_URL`. O `.env.example` explica onde
achar cada um. **Nunca a chave secreta**: o protótipo original vazou a `service_role` dentro do
APK, e a Fase 0 inteira foi fechar isso.

### Se o projeto Supabase não existir mais

1. Crie um projeto novo e faça `supabase link --project-ref <novo>`.
2. **Atenção:** as migrations ainda **não aplicam num banco vazio**. A primeira,
   `20260809052924`, mexe em tabelas que ela não cria, porque o schema do protótipo ficou
   arquivado em `docs/schema_snapshot.sql` em vez de virar migration 0000 (ADR-012). Para
   recomeçar: aplique `docs/schema_snapshot.sql`, depois `supabase db push`; ou, melhor, escreva
   a migration-base consolidada que o `ROADMAP.md` (Fase 1) já pede.
3. Crie antes, em Authentication no painel, os dois usuários de teste com os e-mails que
   `supabase/seed.sql` cita: ele cria a organização e **liga usuários que já existem** no
   Supabase Auth, não os cria. Depois `supabase/dev_seed.sql` põe dois planos, só um atribuído
   ao técnico — logado como técnico o app deve mostrar um campo, como suporte, dois.
4. Crie a senha do `powersync_role` à mão, recrie a instância no PowerSync, e cole
   `supabase/sync_streams.yaml` no painel dela.
5. Rode `supabase/tests/rls_test.sql` — 13 asserções numa transação desfeita, incluindo a de que
   um técnico de uma organização não vê nada de outra.

---

## 3. A arquitetura em uma página

**Offline-first:** o técnico fica até dois dias sem sinal. O app lê e grava **só** no SQLite
local; o PowerSync sincroniza separado, quando há rede.

```
lib/
  domain/entities/        entidades puras, sem import de Flutter/Supabase/PowerSync (campo.dart)
  data/local/             schema do PowerSync (19 tabelas)
  data/remote/            conector de upload: reenvia a fila pelo PostgREST como o usuário logado
  data/repositories/      a única coisa que a UI pode tocar (plano_repository.dart)
  sync/                   sync_service.dart: abrir o banco local não toca a rede
  screens/                telas ainda do protótipo, sendo migradas para features/
supabase/
  migrations/             todas as mudanças de schema (regra dura 7)
  sync_streams.yaml       o que cada aparelho recebe: referência, campos do técnico, org inteira
  tests/rls_test.sql
```

Três ideias carregam o desenho:

1. **Autorização no Postgres** (RLS em toda tabela) para o que sobe e para leituras pela API.
   **O que desce para o aparelho não passa por RLS** — o `powersync_role` tem BYPASSRLS — então
   ali quem protege é o `sync_streams.yaml`. Um erro nele é vazamento entre organizações.
2. **UUID gerado no cliente**, então reenviar depois de uma falha não duplica (ADR-009), e
   **soft delete** que se propaga como lápide (ADR-005).
3. **Vocabulário é dado** (`parametro`, ADR-014), mas o papel do usuário é `CHECK` no schema —
   de propósito, porque o filtro do sync confia nele.

---

## 4. Onde parou

- **Fases 0, 1 e 2 feitas**, com três pendências registradas: trocar a senha do banco (ela
  apareceu numa transcrição em 2026-08-09), a tabela de auditoria, e a migration-base que faça o
  schema aplicar do zero.
- **Fase 3 (PowerSync) escrita e não validada**: schema local, conector, streams e serviço
  existem, e o teste de verdade — modo avião, abrir a frio, a lista de campos aparece — nunca foi
  rodado. **É por aí que se recomeça.**
- **Fase 4 começou** com uma fatia: "Meus Campos" lê do SQLite local por um repositório.
- Fases 5 a 10 (login offline, fluxo do técnico, fotos, conflitos, demais atividades, piloto)
  não começaram.

O último commit antes da pausa também troca `value:` por `initialValue:` num
`DropdownButtonFormField` (`assign_plano.dart`), que o Flutter novo marcava como obsoleto.

---

## 5. Relação com o Plant Management

O Plant Management (`leandroneets/plant-management`, privado) é o sistema da planta: começa onde
este termina, no caminhão saindo do campo. Os dois **não compartilham banco nem tabela**; o elo
entre campo e planta seria por chave de negócio (número do campo, ordem de compra do SAP), e a
rastreabilidade de ponta a ponta ficaria num relatório no Databricks da empresa.
