import 'package:flutter/material.dart';

/// User-creation UI, kept as the layout reference for Phase 5.
///
/// The original version called `auth.admin.createUser` from the app, which
/// required the `service_role` key to ship inside the APK and bypassed RLS
/// entirely (docs/ASSESSMENT.md). That call is gone, along with the `usuarios`
/// insert that followed it — without the auth call it only produced rows with
/// no matching `auth.users` identity. Creation moves to a role-checked Supabase
/// Edge Function in Phase 5; until then this form is deliberately inert.
class CreateUserPage extends StatefulWidget {
  const CreateUserPage({super.key});

  @override
  State<CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nomeController = TextEditingController();

  String? _tipoUsuario = 'Tecnico';

  final List<String> _tipos = ['Tecnico', 'Supervisor', 'Suporte'];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nomeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar Novo Usuário')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'A criação de usuários passará a ser feita pelo servidor. '
                  'Indisponível nesta versão.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Senha'),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _tipoUsuario,
              items: _tipos
                  .map((tipo) =>
                      DropdownMenuItem(value: tipo, child: Text(tipo)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _tipoUsuario = value;
                });
              },
              decoration: const InputDecoration(labelText: 'Tipo de Usuário'),
            ),
            const SizedBox(height: 20),
            const ElevatedButton(
              onPressed: null, // enabled in Phase 5, via the Edge Function
              child: Text('Criar Usuário'),
            ),
          ],
        ),
      ),
    );
  }
}
