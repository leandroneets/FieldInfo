import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlanoListTecnico extends StatefulWidget {
  const PlanoListTecnico({super.key});

  @override
  State<PlanoListTecnico> createState() => _PlanoListTecnicoState();
}

class _PlanoListTecnicoState extends State<PlanoListTecnico> {
  List<dynamic> planos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPlanos();
  }

  Future<void> _fetchPlanos() async {
    final supabase = Supabase.instance.client;

    // No assignment filter here on purpose. The RLS policy `plano_select`
    // already restricts a técnico to his assigned fields, so filtering again in
    // the client would duplicate the rule in a second place where it could
    // drift. Authorization lives in Postgres (CLAUDE.md hard rule 4); this
    // query just asks for what the caller is allowed to see.
    //
    // fazenda and gleba are now separate tables, so they are embedded rather
    // than read as text columns off the plan row.
    final response = await supabase
        .from('plano_producao')
        .select('''
          id,
          num_campo,
          setor,
          hectare,
          modo_colheita,
          gleba (
            nome,
            fazenda ( nome )
          )
        ''')
        .isFilter('deleted_at', null)
        .order('num_campo');

    setState(() {
      planos = response;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (planos.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Nenhum campo atribuído a você.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Campos Atribuídos')),
      body: ListView.builder(
        itemCount: planos.length,
        itemBuilder: (context, index) {
          final plano = planos[index];
          final gleba = plano['gleba'] as Map<String, dynamic>?;
          final fazenda = gleba?['fazenda'] as Map<String, dynamic>?;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(
                  'Campo ${plano['num_campo']} - ${fazenda?['nome'] ?? 'Fazenda não informada'}'),
              subtitle: Text(
                  'Gleba: ${gleba?['nome'] ?? '-'} | Setor: ${plano['setor'] ?? '-'}\n'
                  'Modo de Colheita: ${plano['modo_colheita'] ?? '-'}'),
            ),
          );
        },
      ),
    );
  }
}
