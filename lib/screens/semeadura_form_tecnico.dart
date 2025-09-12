import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SemeaduraFormTecnico extends StatefulWidget {
  const SemeaduraFormTecnico({super.key});

  @override
  State<SemeaduraFormTecnico> createState() => _SemeaduraFormTecnicoState();
}

class _SemeaduraFormTecnicoState extends State<SemeaduraFormTecnico> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  // Dropdown de planos (apenas os atribuídos ao técnico)
  String? _selectedPlanoId;
  List<Map<String, dynamic>> _planos = [];

  // Campos de data
  DateTime? _dataInicioFemea;
  DateTime? _dataFimFemea;
  DateTime? _dataInicioM1;
  DateTime? _dataFimM1;
  DateTime? _dataInicioM2;
  DateTime? _dataFimM2;
  DateTime? _dataInicioM3;
  DateTime? _dataFimM3;
  DateTime? _dataLiberacaoPivo;

  // Campos numéricos
  final _espMxM = TextEditingController();
  final _espFxM = TextEditingController();
  final _espFxF = TextEditingController();
  final _propSemeadura = TextEditingController();

  // Campos texto
  String? _tipoEspacamento; // enum livre por enquanto
  String? _statusSemeadura; // enum livre por enquanto
  final _observacoes = TextEditingController();

  final _tiposEspac = const ['Convencional', 'Duplas', 'Alternado', 'Outro'];
  final _statusOpts = const ['Planejado', 'Em execução', 'Concluído', 'Parcial', 'Cancelado'];

  @override
  void initState() {
    super.initState();
    _loadPlanosAtribuidos();
  }

  @override
  void dispose() {
    _espMxM.dispose();
    _espFxM.dispose();
    _espFxF.dispose();
    _propSemeadura.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _loadPlanosAtribuidos() async {
    final sb = Supabase.instance.client;
    final email = sb.auth.currentUser?.email;

    try {
      // Busca planos atribuídos ao técnico logado
      if (email == null) {
  setState(() {
    _planos = [];
    _loading = false;
  });
  return;
}

final rows = await sb
    .from('plano_producao')
    .select('''
      id_plano,
      num_campo,
      fazenda,
      usuario_plano!inner(
        usuarios(
          email
        )
      )
    ''')
    .eq('usuario_plano.usuarios.email', email);


      setState(() {
        _planos = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar planos: $e')),
        );
      }
    }
  }

  Future<void> _pickDate(BuildContext context, DateTime? current, ValueChanged<DateTime?> onPicked) async {
    final now = DateTime.now();
    final initial = current ?? now;
    final first = DateTime(now.year - 2, 1, 1);
    final last  = DateTime(now.year + 2, 12, 31);

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date != null) {
      onPicked(DateTime(date.year, date.month, date.day));
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  }

  double? _parseNum(String? s) {
    if (s == null) return null;
    // Aceita vírgula ou ponto
    final normalized = s.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<void> _save() async {
    if (_selectedPlanoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um campo (plano).')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
     final payload = {
  'id_plano': _selectedPlanoId,
  'data_inicio_femea': _dataInicioFemea?.toIso8601String(),
  'data_fim_femea': _dataFimFemea?.toIso8601String(),
  'data_inicio_macho1': _dataInicioM1?.toIso8601String(),
  'data_fim_macho1': _dataFimM1?.toIso8601String(),
  'data_inicio_macho2': _dataInicioM2?.toIso8601String(),
  'data_fim_macho2': _dataFimM2?.toIso8601String(),
  'data_inicio_macho3': _dataInicioM3?.toIso8601String(),
  'data_fim_macho3': _dataFimM3?.toIso8601String(),
  'espacamentomxm': _parseNum(_espMxM.text),
  'espacamentofxm': _parseNum(_espFxM.text),
  'espacamentofxf': _parseNum(_espFxF.text),
  'proporcaosemeadura': _parseNum(_propSemeadura.text),
  'tipoespacamento': _tipoEspacamento,
  'dataliberacaopivo': _dataLiberacaoPivo?.toIso8601String(),
  'status_semeadura': _statusSemeadura,
  'observacoes': _observacoes.text.isEmpty ? null : _observacoes.text,
};


      await Supabase.instance.client.from('semeadura').insert(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semeadura registrada com sucesso!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Semeadura')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child:
        ListView(
          children: [
            // Escolha do Plano
            DropdownButtonFormField<String>(
              value: _selectedPlanoId,
              decoration: const InputDecoration(labelText: 'Campo (Plano atribuído)'),
              items: _planos.map((p) {
                final id = p['id_plano'].toString();
                final titulo = 'Campo ${p['num_campo']} — ${p['fazenda'] ?? '-'}';
                return DropdownMenuItem<String>(value: id, child: Text(titulo));
              }).toList(),
              onChanged: (v) => setState(() => _selectedPlanoId = v),
              validator: (v) => v == null ? 'Selecione um plano' : null,
            ),

            const SizedBox(height: 16),
            const Text('Datas Fêmea', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: const Text('Início (Fêmea)'),
                    subtitle: Text(_fmt(_dataInicioFemea)),
                    onTap: () => _pickDate(context, _dataInicioFemea, (d) => setState(()=> _dataInicioFemea = d)),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('Fim (Fêmea)'),
                    subtitle: Text(_fmt(_dataFimFemea)),
                    onTap: () => _pickDate(context, _dataFimFemea, (d) => setState(()=> _dataFimFemea = d)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Text('Datas Macho 1', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: const Text('Início'),
                    subtitle: Text(_fmt(_dataInicioM1)),
                    onTap: () => _pickDate(context, _dataInicioM1, (d) => setState(()=> _dataInicioM1 = d)),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('Fim'),
                    subtitle: Text(_fmt(_dataFimM1)),
                    onTap: () => _pickDate(context, _dataFimM1, (d) => setState(()=> _dataFimM1 = d)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Text('Datas Macho 2', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: const Text('Início'),
                    subtitle: Text(_fmt(_dataInicioM2)),
                    onTap: () => _pickDate(context, _dataInicioM2, (d) => setState(()=> _dataInicioM2 = d)),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('Fim'),
                    subtitle: Text(_fmt(_dataFimM2)),
                    onTap: () => _pickDate(context, _dataFimM2, (d) => setState(()=> _dataFimM2 = d)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Text('Datas Macho 3', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: const Text('Início'),
                    subtitle: Text(_fmt(_dataInicioM3)),
                    onTap: () => _pickDate(context, _dataInicioM3, (d) => setState(()=> _dataInicioM3 = d)),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('Fim'),
                    subtitle: Text(_fmt(_dataFimM3)),
                    onTap: () => _pickDate(context, _dataFimM3, (d) => setState(()=> _dataFimM3 = d)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            ListTile(
              title: const Text('Data Liberação Pivô'),
              subtitle: Text(_fmt(_dataLiberacaoPivo)),
              onTap: () => _pickDate(context, _dataLiberacaoPivo, (d) => setState(()=> _dataLiberacaoPivo = d)),
            ),

            const SizedBox(height: 12),
            TextFormField(
              controller: _espMxM,
              decoration: const InputDecoration(labelText: 'Espaçamento MxM'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (_) {
                final v = _espMxM.text.trim();
                if (v.isEmpty) return null; // opcional
                if (_parseNum(v) == null) return 'Número inválido';
                return null;
              },
            ),
            TextFormField(
              controller: _espFxM,
              decoration: const InputDecoration(labelText: 'Espaçamento FxM'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (_) {
                final v = _espFxM.text.trim();
                if (v.isEmpty) return null;
                if (_parseNum(v) == null) return 'Número inválido';
                return null;
              },
            ),
            TextFormField(
              controller: _espFxF,
              decoration: const InputDecoration(labelText: 'Espaçamento FxF'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (_) {
                final v = _espFxF.text.trim();
                if (v.isEmpty) return null;
                if (_parseNum(v) == null) return 'Número inválido';
                return null;
              },
            ),
            TextFormField(
              controller: _propSemeadura,
              decoration: const InputDecoration(labelText: 'Proporção Semeadura'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (_) {
                final v = _propSemeadura.text.trim();
                if (v.isEmpty) return null;
                if (_parseNum(v) == null) return 'Número inválido';
                return null;
              },
            ),

            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _tipoEspacamento,
              decoration: const InputDecoration(labelText: 'Tipo de Espaçamento'),
              items: _tiposEspac
                  .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _tipoEspacamento = v),
            ),
            DropdownButtonFormField<String>(
              value: _statusSemeadura,
              decoration: const InputDecoration(labelText: 'Status Semeadura'),
              items: _statusOpts
                  .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _statusSemeadura = v),
            ),
            TextFormField(
              controller: _observacoes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    )
    );
  }
}
