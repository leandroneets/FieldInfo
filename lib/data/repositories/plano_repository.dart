import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/campo.dart';

/// Reads production plans from the local database.
///
/// The only path the UI is allowed to take to this data (CLAUDE.md hard rule 2).
/// Every query runs against local SQLite, never the network (ADR-004) — which
/// is what makes the screens work with no connectivity at all.
///
/// [watchCamposAtribuidos] returns a *stream*: PowerSync re-emits whenever the
/// underlying rows change, so a background sync updates the list without the UI
/// asking. That is the property ADR-011 chose Riverpod for, and Phase 4 will
/// wrap these streams in providers.
class PlanoRepository {
  PlanoRepository(this._db);

  final PowerSyncDatabase _db;

  /// The signed-in user's id, which equals `usuario.id` (ADR-008).
  ///
  /// Read here rather than in the widget so the UI layer never touches Supabase.
  /// Phase 5 replaces this with an injected session service; until then the
  /// dependency is contained to the data layer, which is where it belongs.
  String? get _currentUserId =>
      Supabase.instance.client.auth.currentUser?.id;

  /// The fields assigned to the signed-in técnico, ordered as the field team
  /// refers to them.
  ///
  /// The join to `usuario_plano` is not redundant with the sync rules. A
  /// técnico's device only ever holds his own fields, but a supervisor's device
  /// holds the whole organizacao — without this filter, "Meus Campos" would
  /// show a supervisor every field in the company.
  ///
  /// `deleted_at IS NULL` filters tombstones. They are excluded from the sync
  /// streams too, so this is belt-and-braces rather than the only guard.
  Stream<List<Campo>> watchCamposAtribuidos() {
    final userId = _currentUserId;
    if (userId == null) return Stream.value(const []);

    return _db.watch(
      '''
      SELECT
        p.id            AS id,
        p.num_campo     AS num_campo,
        p.setor         AS setor,
        p.hectare       AS hectare,
        p.modo_colheita AS modo_colheita,
        g.nome          AS gleba,
        f.nome          AS fazenda
      FROM plano_producao p
      INNER JOIN usuario_plano up
              ON up.id_plano = p.id
             AND up.id_usuario = ?
             AND up.deleted_at IS NULL
      LEFT JOIN gleba   g ON g.id = p.id_gleba   AND g.deleted_at IS NULL
      LEFT JOIN fazenda f ON f.id = g.id_fazenda AND f.deleted_at IS NULL
      WHERE p.deleted_at IS NULL
      ORDER BY p.num_campo
      ''',
      parameters: [userId],
    ).map(
      // Mapped inline rather than through a named helper: the row type comes
      // from sqlite3, which is only a transitive dependency here, so naming it
      // would mean importing a package this project does not declare.
      (results) => [
        for (final row in results)
          Campo(
            id: row['id'] as String,
            numCampo: row['num_campo'] as int,
            fazenda: row['fazenda'] as String?,
            gleba: row['gleba'] as String?,
            setor: row['setor'] as String?,
            // SQLite stores numeric as REAL or INTEGER depending on the value,
            // so widen rather than casting straight to double.
            hectare: (row['hectare'] as num?)?.toDouble(),
            modoColheita: row['modo_colheita'] as String?,
          ),
      ],
    );
  }

  /// How many fields the device currently holds for this user. Useful as a
  /// diagnostic while sync is being brought up.
  Future<int> contarCampos() async {
    final userId = _currentUserId;
    if (userId == null) return 0;

    final row = await _db.get(
      '''
      SELECT count(*) AS n
      FROM plano_producao p
      INNER JOIN usuario_plano up
              ON up.id_plano = p.id
             AND up.id_usuario = ?
             AND up.deleted_at IS NULL
      WHERE p.deleted_at IS NULL
      ''',
      [userId],
    );
    return row['n'] as int;
  }
}
