/// A field the technician is responsible for: one production plan, resolved
/// against its farm and gleba.
///
/// Pure Dart by design (CLAUDE.md). No Flutter, Supabase or PowerSync imports —
/// this type must be constructible in a unit test with no database and no
/// widget tree.
///
/// `Campo` rather than `PlanoProducao` because "campo" is what the técnico
/// calls it and what the home screen is named after; the plan is the storage
/// concept, the field is the domain one.
class Campo {
  const Campo({
    required this.id,
    required this.numCampo,
    this.fazenda,
    this.gleba,
    this.setor,
    this.hectare,
    this.modoColheita,
  });

  /// Client-generated UUID (ADR-009).
  final String id;

  /// The number the field team says out loud. Unique per safra within a tenant.
  final int numCampo;

  final String? fazenda;
  final String? gleba;
  final String? setor;
  final double? hectare;

  /// `codigo` from the parametro domain `modo_colheita` — currently AXF or
  /// Espiga. This is the stored code, not a display label; the label lives in
  /// parametro.rotulo (ADR-014).
  final String? modoColheita;

  /// What the list row shows as its title.
  String get titulo => 'Campo $numCampo${fazenda == null ? '' : ' — $fazenda'}';

  @override
  String toString() => 'Campo($numCampo, $fazenda/$gleba)';
}
