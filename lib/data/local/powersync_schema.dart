import 'package:powersync/powersync.dart';

/// The local SQLite schema PowerSync maintains on the device.
///
/// This mirrors the Postgres schema, with three deliberate differences:
///
/// 1. **`id` is never declared.** PowerSync supplies it on every table as the
///    row key. Declaring it again is an error.
///
/// 2. **Generated columns are excluded.** Postgres computes the `*_dominio`
///    columns (see ADR-014) and rejects any attempt to write them. If they
///    appeared here they would be included in upload payloads and every write
///    would fail.
///
/// 3. **Only three column types exist**: text, integer and real. So:
///    - `uuid`, `text`, `date`, `timestamptz` → [Column.text] (ISO-8601 strings)
///    - `boolean` → [Column.integer] (0 / 1)
///    - `numeric`, `double` → [Column.real]
///    - `bigint`, `smallint`, `integer` → [Column.integer]
///
///    Note `numeric` becoming `real` means moisture readings are held as
///    floating point on the device. Postgres keeps the exact `numeric(5,2)`, so
///    the authoritative value is never lossy; only the local copy is. Format
///    for display with `intl`, never by string-truncating a double.
const schema = Schema([
  // ---------------------------------------------------------------------
  // Tenant and identity
  // ---------------------------------------------------------------------
  Table('organizacao', [
    Column.text('nome'),
    Column.integer('ativa'),
    ..._sync,
  ]),

  Table('usuario', [
    Column.text('nome'),
    Column.text('email'),
    Column.text('papel'),
    Column.integer('ativo'),
    ..._sync,
  ]),

  // ---------------------------------------------------------------------
  // Master data. All of this must be present offline — docs/DOMAIN.md
  // requires every reference dropdown to work with no connectivity.
  // ---------------------------------------------------------------------
  Table('safra', [
    Column.text('codigo'),
    Column.text('data_inicio'),
    Column.text('data_fim'),
    Column.integer('ativa'),
    ..._sync,
  ]),

  Table('material', [
    Column.text('hibrido'),
    Column.text('macho'),
    Column.text('femea'),
    Column.text('cultura'),
    Column.real('umidade_min'),
    Column.real('umidade_max'),
    ..._sync,
  ]),

  Table('fazenda', [
    Column.text('nome'),
    Column.text('cooperado'),
    ..._sync,
  ]),

  Table('gleba', [
    Column.text('id_fazenda'),
    Column.text('nome'),
    ..._sync,
  ], indexes: [
    Index('gleba_fazenda', [IndexedColumn('id_fazenda')]),
  ]),

  /// Admin-managed vocabulary (ADR-014). This is what populates every dropdown
  /// offline; without it the técnico cannot pick a status or a stage.
  Table('parametro', [
    Column.text('dominio'),
    Column.text('codigo'),
    Column.text('rotulo'),
    Column.integer('ordem'),
    Column.integer('ativo'),
    Column.integer('bloqueia_edicao'),
    ..._sync,
  ], indexes: [
    Index('parametro_dominio', [IndexedColumn('dominio'), IndexedColumn('ordem')]),
  ]),

  // ---------------------------------------------------------------------
  // Planning and assignment
  // ---------------------------------------------------------------------
  Table('plano_producao', [
    Column.text('id_safra'),
    Column.text('id_material'),
    Column.text('id_gleba'),
    Column.integer('num_campo'),
    Column.real('hectare'),
    Column.text('setor'),
    Column.text('modo_colheita'),
    Column.integer('ativo'),
    ..._sync,
  ], indexes: [
    Index('plano_safra', [IndexedColumn('id_safra')]),
  ]),

  Table('usuario_plano', [
    Column.text('id_usuario'),
    Column.text('id_plano'),
    ..._sync,
  ], indexes: [
    Index('usuario_plano_plano', [IndexedColumn('id_plano')]),
  ]),

  // ---------------------------------------------------------------------
  // Field activities. Every one carries id_plano so it can be bucketed by
  // assignment (see 20260827024517) — and so the app can list a field's
  // history with a single indexed lookup.
  // ---------------------------------------------------------------------
  Table('semeadura', [
    Column.text('id_plano'),
    Column.text('data_liberacao_pivo'),
    Column.text('inicio_semeadura_femea'),
    Column.text('fim_semeadura_femea'),
    Column.text('inicio_semeadura_macho1'),
    Column.text('fim_semeadura_macho1'),
    Column.text('inicio_semeadura_macho2'),
    Column.text('fim_semeadura_macho2'),
    Column.text('inicio_semeadura_macho3'),
    Column.text('fim_semeadura_macho3'),
    Column.real('espacamento_mxm'),
    Column.real('espacamento_fxm'),
    Column.real('espacamento_fxf'),
    Column.text('proporcao_semeadura'),
    Column.text('status_semeadura'),
    Column.text('tipo_espacamento'),
    Column.text('tipo_lancamento'),
    Column.text('observacao'),
    ..._sync,
  ], indexes: [
    Index('semeadura_plano', [IndexedColumn('id_plano')]),
  ]),

  Table('semeadura_basica', [
    Column.text('id_semeadura'),
    Column.text('id_plano'),
    Column.text('lote_basica_femea'),
    Column.real('kg_femea'),
    Column.text('lote_femea_esteril'),
    Column.text('peneira_femea_esteril'),
    Column.real('kg_femea_esteril'),
    Column.text('geracao'),
    Column.text('lote_basica_macho'),
    Column.text('peneira_macho'),
    Column.real('kg_macho'),
    Column.text('nota_fiscal_femea'),
    Column.text('nota_fiscal_macho'),
    ..._sync,
  ], indexes: [
    Index('semeadura_basica_plano', [IndexedColumn('id_plano')]),
  ]),

  Table('estadio_fenologico', [
    Column.text('id_semeadura'),
    Column.text('id_plano'),
    Column.text('estadio'),
    Column.text('data_apontamento'),
    Column.text('observacao'),
    Column.integer('gerar_alerta'),
    ..._sync,
  ], indexes: [
    Index('estadio_plano', [
      IndexedColumn('id_plano'),
      IndexedColumn.descending('data_apontamento'),
    ]),
  ]),

  Table('bioensaio_checklist', [
    Column.text('id_plano'),
    Column.integer('esta_na_area_2anos'),
    Column.integer('gerente_2anos'),
    Column.integer('herbicida_persiste'),
    Column.integer('daninha'),
    Column.integer('travamento_soja'),
    Column.integer('soja_anterior'),
    Column.integer('calagem'),
    Column.integer('revolvimento_solo'),
    Column.text('cultura_anterior'),
    Column.text('ciclo_cultura_anterior'),
    Column.text('herbicida_aplicado'),
    Column.real('dose_herbicida'),
    Column.text('tipo_dosagem_herbicida'),
    Column.text('prod_trav_soja'),
    Column.real('dosagem_trav_soja'),
    Column.text('tipo_dose_trav_soja'),
    Column.text('materia_organica'),
    Column.text('tipo_de_solo'),
    Column.real('ph_solo'),
    Column.text('resultado'),
    ..._sync,
  ], indexes: [
    Index('checklist_plano', [IndexedColumn('id_plano')]),
  ]),

  Table('bioensaio', [
    Column.text('id_checklist'),
    Column.text('id_plano'),
    Column.text('tipo_avaliacao'),
    Column.text('data_avaliacao'),
    Column.integer('linhagem1'),
    Column.integer('linhagem2'),
    Column.integer('linhagem3'),
    Column.integer('pop_l1'),
    Column.integer('pop_l2'),
    Column.integer('pop_l3'),
    Column.real('percentual_pop_l1'),
    Column.real('percentual_pop_l2'),
    Column.real('percentual_pop_l3'),
    Column.text('status'),
    Column.text('observacao'),
    ..._sync,
  ], indexes: [
    Index('bioensaio_plano', [IndexedColumn('id_plano')]),
  ]),

  Table('amostra_umidade', [
    Column.text('id_plano'),
    Column.text('data_amostra'),
    Column.integer('dividir_gleba'),
    Column.real('percentil'),
    Column.integer('liberado_colheita'),
    Column.text('observacao'),
    ..._sync,
  ], indexes: [
    Index('amostra_plano', [
      IndexedColumn('id_plano'),
      IndexedColumn.descending('data_amostra'),
    ]),
  ]),

  /// One row per reading. The count varies — the server-side view averages over
  /// the readings that exist, and the client must do the same. Never divide by
  /// a fixed 32.
  Table('amostra_umidade_leitura', [
    Column.text('id_amostra'),
    Column.text('id_plano'),
    Column.integer('sequencia'),
    Column.real('valor'),
    ..._sync,
  ], indexes: [
    Index('leitura_amostra', [
      IndexedColumn('id_amostra'),
      IndexedColumn('sequencia'),
    ]),
  ]),

  Table('ficha_colheita', [
    Column.text('id_plano'),
    Column.text('numero_ficha'),
    Column.integer('utilizada'),
    ..._sync,
  ], indexes: [
    Index('ficha_plano', [IndexedColumn('id_plano')]),
  ]),

  Table('carga', [
    Column.text('id_ficha'),
    Column.text('id_plano'),
    Column.text('tipo_colheita'),
    Column.text('fim_enchimento'),
    Column.text('motorista'),
    Column.text('placa'),
    Column.integer('campo_finalizado'),
    Column.real('umidade'),
    Column.text('recebimento'),
    Column.text('estado_carga'),
    Column.text('volume_carga'),
    ..._sync,
  ], indexes: [
    Index('carga_plano', [IndexedColumn('id_plano')]),
  ]),

  Table('alerta_producao', [
    Column.text('id_plano'),
    Column.text('estadio'),
    Column.text('tipo_alerta'),
    Column.text('observacao'),
    Column.text('resolvido_em'),
    ..._sync,
  ], indexes: [
    Index('alerta_plano', [IndexedColumn('id_plano')]),
  ]),
]);

/// The columns CLAUDE.md requires on every synced table.
///
/// `id` is absent because PowerSync provides it. `revision` and `deleted_at`
/// are present because the client needs both: `revision` for the Phase 8
/// conflict check, and `deleted_at` because tombstones sync like any other row
/// and the UI is what filters them out (ADR-005).
const _sync = [
  Column.text('org_id'),
  Column.text('created_at'),
  Column.text('created_by'),
  Column.text('updated_at'),
  Column.text('updated_by'),
  Column.integer('revision'),
  Column.text('deleted_at'),
];
