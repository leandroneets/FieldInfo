import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AssignPlanoPage extends StatefulWidget {
  const AssignPlanoPage({super.key});

  @override
  State<AssignPlanoPage> createState() => _AssignPlanoPageState();
}

class _AssignPlanoPageState extends State<AssignPlanoPage> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  String? _selectedPlanoId;
  String? _selectedUsuarioId;

  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _tecnicos = [];
  List<Map<String, dynamic>> _atribuicoes = []; // lista de usuario_plano com joins
  Map<String, int> _contagemPorPlano = {};      // id_plano -> qtd técnicos

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    setState(() {
      _loading = true;
    });
    final sb = Supabase.instance.client;

    try {
      // Planos
      final planos = await sb
          .from('plano_producao')
          .select('id_plano, num_campo, fazenda')
          .order('criado_em', ascending: false);

      // Técnicos
      final tecnicos = await sb
          .from('usuarios')
          .select('id_usuario, nome, email, tipo_usuario')
          .eq('tipo_usuario', 'Tecnico')
          .order('nome', ascending: true);

      // Atribuições atuais (join nos FKs)
      final atribuicoes = await sb
          .from('usuario_plano')
          .select('''
            id_usuario_plano,
            plano_producao ( id_plano, num_campo, fazenda ),
            usuarios ( id_usuario, nome, email )
          ''')
          .order('id_usuario_plano', ascending: false);

      // Montar contagem por plano
      final Map<String, int> cont = {};
      for (final a in atribuicoes) {
        final pid = a['plano_producao']?['id_plano']?.toString();
        if (pid == null) continue;
        cont[pid] = (cont[pid] ?? 0) + 1;
      }

      setState(() {
        _planos = List<Map<String, dynamic>>.from(planos);
        _tecnicos = List<Map<String, dynamic>>.from(tecnicos);
        _atribuicoes = List<Map<String, dynamic>>.from(atribuicoes);
        _contagemPorPlano = cont;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados: $e')),
        );
      }
    }
  }

  Future<void> _assign() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await Supabase.instance.client.from('usuario_plano').insert({
        'id_usuario': _selectedUsuarioId,
        'id_plano': _selectedPlanoId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plano atribuído com sucesso!')),
      );
      await _loadEverything(); // atualiza lista e contagens
    } on PostgrestException catch (e) {
      final msg = e.code == '23505'
          ? 'Este plano já está atribuído a este técnico.'
          : 'Erro: ${e.message}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unassign(String idUsuarioPlano) async {
    try {
      await Supabase.instance.client
          .from('usuario_plano')
          .delete()
          .eq('id_usuario_plano', idUsuarioPlano);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Atribuição removida.')),
      );
      await _loadEverything();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao desatribuir: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Atribuir / Desatribuir Planos')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // --------- Form de Atribuição ---------
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Plano (Campo / Fazenda)'),
                    initialValue: _selectedPlanoId,
                    items: _planos
                        .map((p) {
                          final id = p['id_plano'].toString();
                          final qtd = _contagemPorPlano[id] ?? 0;
                          final titulo = 'Campo ${p['num_campo']} — ${p['fazenda'] ?? '-'}'
                              '  (${qtd} técnico${qtd == 1 ? '' : 's'})';
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(titulo),
                          );
                        })
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPlanoId = v),
                    validator: (v) => v == null ? 'Selecione um plano' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Técnico'),
                    value: _selectedUsuarioId,
                    items: _tecnicos
                        .map((t) => DropdownMenuItem<String>(
                              value: t['id_usuario'].toString(),
                              child: Text('${t['nome']}  (${t['email']})'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedUsuarioId = v),
                    validator: (v) => v == null ? 'Selecione um técnico' : null,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _assign,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    label: const Text('Atribuir'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),

            // --------- Lista de Atribuições ---------
            const Text(
              'Atribuições atuais',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_atribuicoes.isEmpty)
              const Text('Nenhuma atribuição realizada.')
            else
              ..._atribuicoes.map((a) {
                final idUsuarioPlano = a['id_usuario_plano'].toString();
                final plano = a['plano_producao'] ?? {};
                final usuario = a['usuarios'] ?? {};
                final titulo =
                    'Campo ${plano['num_campo'] ?? '-'} — ${plano['fazenda'] ?? '-'}';
                final subtitulo = '${usuario['nome'] ?? '-'}  (${usuario['email'] ?? '-'})';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    title: Text(titulo),
                    subtitle: Text(subtitulo),
                    trailing: IconButton(
  icon: const Icon(Icons.link_off), // ✅ ícone disponível
  tooltip: 'Desatribuir',
  onPressed: () => _unassign(idUsuarioPlano),
),

                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
