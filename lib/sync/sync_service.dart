import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/powersync_schema.dart';
import '../data/remote/powersync_connector.dart';

/// Owns the local database and the sync connection.
///
/// The local SQLite file is the source of truth for reads and writes (ADR-004).
/// The UI never awaits the network: it queries [db], and PowerSync moves data
/// in the background.
///
/// Deliberately not a Riverpod provider yet. ADR-011 chose Riverpod, and Phase 4
/// will expose this through one alongside the repositories. Keeping it a plain
/// singleton for now avoids inventing a provider shape that the repository layer
/// would immediately replace.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  PowerSyncDatabase? _db;

  /// The local database. Throws if used before [open] — that would mean a
  /// widget tried to read data before the app finished starting, which is a
  /// programming error rather than a runtime condition to handle.
  PowerSyncDatabase get db {
    final database = _db;
    if (database == null) {
      throw StateError('SyncService.open() must be awaited before using db.');
    }
    return database;
  }

  bool get isOpen => _db != null;

  /// Opens the local database. Safe to call once, at startup.
  ///
  /// Note this does NOT connect. Opening works with no network at all, which is
  /// the point: a cold start in airplane mode must still reach local data.
  Future<void> open() async {
    if (_db != null) return;

    final dir = await getApplicationSupportDirectory();
    final database = PowerSyncDatabase(
      schema: schema,
      path: p.join(dir.path, 'fieldinfo.db'),
    );
    await database.initialize();
    _db = database;
  }

  /// Connects to PowerSync using the current Supabase session.
  ///
  /// Called after login, and again whenever the session changes. Does nothing
  /// if nobody is signed in — the connector would just return null credentials.
  Future<void> connect() async {
    if (Supabase.instance.client.auth.currentSession == null) return;

    final url = dotenv.env['POWERSYNC_URL'];
    if (url == null || url.isEmpty) {
      throw StateError(
        'POWERSYNC_URL is missing from assets/.env. See assets/.env.example.',
      );
    }

    await db.connect(connector: FieldInfoConnector(powerSyncUrl: url));
  }

  /// Disconnects and clears all local data.
  ///
  /// Used on sign-out. `disconnectAndClear` is the correct call rather than
  /// plain `disconnect`: leaving one user's synced rows on a shared company
  /// device for the next person to open is a data-leak, and the rows would in
  /// any case be wrong for a different assignment set.
  ///
  /// This destroys anything still queued for upload. Phase 5 must refuse to
  /// sign out while [hasPendingUploads] is true, or a técnico could lose a day
  /// of work by tapping the wrong button.
  Future<void> signOutAndClear() async {
    await _db?.disconnectAndClear();
  }

  /// Live sync state, for the status indicator the UI shows.
  Stream<SyncStatus> get statusStream => db.statusStream;

  SyncStatus get status => db.currentStatus;

  /// True while local changes have not yet reached the server.
  ///
  /// This is what a "pending" badge on a record should reflect, and what
  /// sign-out must check.
  Future<bool> hasPendingUploads() async {
    return (await db.getUploadQueueStats()).count > 0;
  }

  /// Keeps the connection in step with the auth session: connect on sign-in,
  /// clear on sign-out. Call once during startup.
  StreamSubscription<AuthState> listenToAuth() {
    return Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
          await connect();
        case AuthChangeEvent.signedOut:
          await signOutAndClear();
        default:
          break;
      }
    });
  }
}
