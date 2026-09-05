import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bridges PowerSync to Supabase.
///
/// Two responsibilities:
///
/// * [fetchCredentials] hands PowerSync the user's Supabase access token, so
///   the sync service knows who is connecting and which buckets to send.
/// * [uploadData] replays locally queued writes against PostgREST.
///
/// Uploads deliberately travel through PostgREST as the authenticated user
/// rather than through the replication connection. That means RLS applies to
/// every write: a técnico who somehow queued a change to a field he is not
/// assigned to has it rejected by Postgres, not by client-side code. The
/// download path is governed by Sync Rules instead, because PowerSync's
/// replication role holds BYPASSRLS.
class FieldInfoConnector extends PowerSyncBackendConnector {
  FieldInfoConnector({required this.powerSyncUrl});

  /// The PowerSync instance endpoint, from assets/.env.
  final String powerSyncUrl;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // Returning null tells PowerSync to stay disconnected rather than retry in
    // a tight loop. That is the correct state when nobody is logged in.
    final session = _supabase.auth.currentSession;
    if (session == null) return null;

    return PowerSyncCredentials(
      endpoint: powerSyncUrl,
      token: session.accessToken,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    // Track the operation in flight so a failure can say which row broke,
    // rather than reporting an opaque PostgREST error.
    CrudEntry? current;

    try {
      for (final op in transaction.crud) {
        current = op;
        final table = _supabase.from(op.table);

        switch (op.op) {
          case UpdateType.put:
            // Client-generated UUIDs make this idempotent (ADR-009): a retried
            // upload after an ambiguous failure cannot create a duplicate.
            await table.upsert({'id': op.id, ...?op.opData});

          case UpdateType.patch:
            await table.update(op.opData!).eq('id', op.id);

          case UpdateType.delete:
            // Reached only for a genuine hard delete. Normal deletion sets
            // deleted_at and arrives here as a patch (ADR-005), because a
            // synced row is never hard-deleted.
            await table.delete().eq('id', op.id);
        }
      }

      // Only clears the local queue once every operation in the transaction
      // succeeded. Anything else and the whole batch is retried.
      await transaction.complete();
    } on PostgrestException catch (e) {
      // A 4xx from PostgREST means the server refused this write and always
      // will: an RLS denial, a constraint violation, a value missing from a
      // parametro domain. Retrying forever would wedge the upload queue and
      // silently block every later change the técnico makes — the failure mode
      // that destroys trust in an offline app.
      //
      // Discarding it loses the técnico's work, which ADR-006 forbids, so
      // neither option is acceptable on its own. Phase 8 is where rejected
      // operations get parked for supervisor review. Until that exists, fail
      // loudly rather than pretend: the queue stalls, and the error names the
      // row so it can be diagnosed.
      final fatal = e.code != null &&
          e.code!.startsWith('4') &&
          e.code != '429';

      // ignore: avoid_print
      print(
        'PowerSync upload failed on ${current?.table}/${current?.id} '
        '(${current?.op.name}): ${e.code} ${e.message}'
        '${fatal ? ' — permanent, queue is stalled and needs Phase 8' : ' — will retry'}',
      );

      rethrow;
    }
  }
}
