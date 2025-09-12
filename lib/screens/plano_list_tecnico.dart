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
    final email = supabase.auth.currentUser?.email;

    final response = await supabase
        .from('plano_producao')
        .select('''
          id_plano,
          num_campo,
          fazenda,
          gleba,
          setor,
          modo_colheita,
          usuario_plano!inner(
            id_usuario,
            usuarios (
              email
            )
          )
        ''')
        .eq('usuario_plano.usuarios.email', email ?? '');

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
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text('Campo ${plano['num_campo']} - ${plano['fazenda'] ?? 'Fazenda não informada'}'),
              subtitle: Text(
                  'Gleba: ${plano['gleba'] ?? '-'} | Setor: ${plano['setor'] ?? '-'}\nModo de Colheita: ${plano['modo_colheita'] ?? '-'}'),
            ),
          );
        },
      ),
    );
  }
}
