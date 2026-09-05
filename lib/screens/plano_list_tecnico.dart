import 'package:flutter/material.dart';
// `show SyncStatus` is not tidiness — powersync exports a `Column` class for
// schema definitions, which collides with Flutter's layout widget. Importing
// the package wholesale into any widget file breaks every Column in it.
import 'package:powersync/powersync.dart' show SyncStatus;

import '../data/repositories/plano_repository.dart';
import '../domain/entities/campo.dart';
import '../sync/sync_service.dart';

/// "Meus Campos" — the fields assigned to the signed-in técnico.
///
/// Reads from local SQLite through [PlanoRepository], never from the network.
/// The list renders identically with the radio off; PowerSync fills the local
/// database in the background and the stream re-emits when it does.
///
/// This screen touches no Supabase client and no PowerSync database directly
/// (CLAUDE.md hard rule 2) — only the repository and the sync status.
class PlanoListTecnico extends StatefulWidget {
  const PlanoListTecnico({super.key});

  @override
  State<PlanoListTecnico> createState() => _PlanoListTecnicoState();
}

class _PlanoListTecnicoState extends State<PlanoListTecnico> {
  late final PlanoRepository _repository;
  late final Stream<List<Campo>> _campos;

  @override
  void initState() {
    super.initState();
    _repository = PlanoRepository(SyncService.instance.db);
    _campos = _repository.watchCamposAtribuidos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Campos'),
        bottom: const _SyncStatusBar(),
      ),
      body: StreamBuilder<List<Campo>>(
        stream: _campos,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Mensagem(
              icone: Icons.error_outline,
              texto: 'Erro ao ler os campos: ${snapshot.error}',
            );
          }

          // Only the very first frame has no data. After that the stream always
          // carries a list, so a spinner here never blocks on the network.
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final campos = snapshot.data!;

          if (campos.isEmpty) {
            return const _Mensagem(
              icone: Icons.map_outlined,
              texto: 'Nenhum campo atribuído a você.\n\n'
                  'Se você acabou de entrar, aguarde a primeira sincronização.',
            );
          }

          return ListView.builder(
            itemCount: campos.length,
            itemBuilder: (context, index) {
              final campo = campos[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(campo.titulo),
                  subtitle: Text(
                    'Gleba: ${campo.gleba ?? '-'} | Setor: ${campo.setor ?? '-'}\n'
                    'Colheita: ${campo.modoColheita ?? '-'}'
                    '${campo.hectare == null ? '' : ' | ${campo.hectare} ha'}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A thin strip showing whether the device is connected and whether anything is
/// still waiting to upload.
///
/// Deliberately visible during development: the whole point of Phase 3 is that
/// the list works while this says "offline", and that is much easier to trust
/// when the state is on screen rather than inferred.
class _SyncStatusBar extends StatelessWidget implements PreferredSizeWidget {
  const _SyncStatusBar();

  @override
  Size get preferredSize => const Size.fromHeight(22);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: SyncService.instance.statusStream,
      initialData: SyncService.instance.status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final conectado = status?.connected ?? false;
        final baixando = status?.downloading ?? false;
        final enviando = status?.uploading ?? false;

        final (texto, cor) = switch ((conectado, baixando, enviando)) {
          (false, _, _) => ('Offline — dados locais', Colors.orange),
          (true, true, _) => ('Sincronizando...', Colors.blue),
          (true, _, true) => ('Enviando alterações...', Colors.blue),
          _ => ('Sincronizado', Colors.green),
        };

        return Container(
          width: double.infinity,
          color: cor.withValues(alpha: 0.15),
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cor.shade900),
          ),
        );
      },
    );
  }
}

class _Mensagem extends StatelessWidget {
  const _Mensagem({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(texto, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
