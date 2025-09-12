import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _loading = false;

  final List<String> _tipos = ['Tecnico', 'Supervisor', 'Suporte'];

  Future<void> _createUser() async {
    setState(() => _loading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final nome = _nomeController.text.trim();

    try {
      // Step 1: Create user in Supabase Auth
      final authResponse = await Supabase.instance.client.auth.admin.createUser(
        AdminUserAttributes(
          email: email,
          password: password,
          emailConfirm: true,
        ),
      );

      if (authResponse.user == null) {
        throw Exception("Failed to create auth user");
      }

      // Step 2: Insert into your 'usuarios' table
      await Supabase.instance.client.from('usuarios').insert({
        'email': email,
        'nome': nome,
        'tipo_usuario': _tipoUsuario,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário criado com sucesso!')),
      );

      _emailController.clear();
      _passwordController.clear();
      _nomeController.clear();
      setState(() => _tipoUsuario = 'Tecnico');
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
      appBar: AppBar(title: const Text('Criar Novo Usuário')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
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
            ElevatedButton(
              onPressed: _loading ? null : _createUser,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Criar Usuário'),
            ),
          ],
        ),
      ),
    );
  }
}
