import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreatePlanoPage extends StatefulWidget {
  const CreatePlanoPage({super.key});

  @override
  State<CreatePlanoPage> createState() => _CreatePlanoPageState();
}

class _CreatePlanoPageState extends State<CreatePlanoPage> {
  final _formKey = GlobalKey<FormState>();

  int? _numCampo;
  String? _fazenda;
  String? _gleba;
  String? _setor;
  String? _modoColheita;
  double? _hectare;

  String? _selectedSafraId;
  String? _selectedMaterialId;

  bool _loading = false;
  List<Map<String, dynamic>> _safras = [];
  List<Map<String, dynamic>> _materiais = [];

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
  }

  Future<void> _fetchDropdownData() async {
    final supabase = Supabase.instance.client;
    final safras = await supabase.from('safra').select('id_safra, nome');
    final materiais = await supabase.from('material').select('id_material, hibrido');

    setState(() {
      _safras = List<Map<String, dynamic>>.from(safras);
      _materiais = List<Map<String, dynamic>>.from(materiais);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    _formKey.currentState!.save();

    try {
      await Supabase.instance.client.from('plano_producao').insert({
        'num_campo': _numCampo,
        'fazenda': _fazenda,
        'gleba': _gleba,
        'setor': _setor,
        'modo_colheita': _modoColheita,
        'hectare': _hectare,
        'id_safra': _selectedSafraId,
        'id_material': _selectedMaterialId,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plano criado com sucesso!')),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo Plano de Produção')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Número do Campo'),
                      keyboardType: TextInputType.number,
                      onSaved: (value) => _numCampo = int.tryParse(value ?? ''),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Campo obrigatório' : null,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Fazenda'),
                      onSaved: (value) => _fazenda = value,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Gleba'),
                      onSaved: (value) => _gleba = value,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Setor'),
                      onSaved: (value) => _setor = value,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Modo de Colheita'),
                      onSaved: (value) => _modoColheita = value,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Hectare'),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      onSaved: (value) => _hectare = double.tryParse(value ?? ''),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedSafraId,
                      decoration: const InputDecoration(labelText: 'Safra'),
                      items: _safras
                          .map((safra) => DropdownMenuItem(
                                value: safra['id_safra'].toString(),
                                child: Text(safra['nome']),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedSafraId = value),
                      validator: (value) =>
                          value == null ? 'Selecione uma safra' : null,
                    ),
                    DropdownButtonFormField<String>(
                      value: _selectedMaterialId,
                      decoration: const InputDecoration(labelText: 'Material'),
                      items: _materiais
                          .map((mat) => DropdownMenuItem(
                                value: mat['id_material'].toString(),
                                child: Text(mat['hibrido']),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _selectedMaterialId = value),
                      validator: (value) =>
                          value == null ? 'Selecione um material' : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: const Text('Salvar Plano'),
                    )
                  ],
                ),
              ),
            ),
    );
  }
}
