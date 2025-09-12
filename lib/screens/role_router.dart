import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_tecnico.dart';     // contém HomeTecnicoPage
import 'home_supervisor.dart';  // contém HomeSupervisor
import 'home_suporte.dart';     // contém HomeSuporte

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  String? _tipoUsuario;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final email = Supabase.instance.client.auth.currentUser?.email;

    if (email == null) {
      setState(() {
        _tipoUsuario = null;
        _loading = false;
      });
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('usuarios')
          .select('tipo_usuario')
          .eq('email', email)
          .maybeSingle();

      setState(() {
        _tipoUsuario = data?['tipo_usuario'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _tipoUsuario = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Redireciona conforme o papel
    if (_tipoUsuario == 'Tecnico') {
      return const HomeTecnicoPage();      // <- nome novo da sua tela do técnico
    } else if (_tipoUsuario == 'Supervisor') {
      return const HomeSupervisor();
    } else if (_tipoUsuario == 'Suporte') {
      return const HomeSuporte();
    }

    // Caso o usuário não esteja na tabela 'usuarios' ou não tenha tipo definido
    return Scaffold(
      appBar: AppBar(title: const Text('Acesso')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Usuário sem papel definido em "usuarios".'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (!mounted) return;
                Navigator.of(context).pop(); // volta para tela de login
              },
              child: const Text('Sair e voltar ao login'),
            ),
          ],
        ),
      ),
    );
  }
}
