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
    // Matched on auth.uid(), not email. usuario.id IS auth.users.id (ADR-008),
    // so identity never depends on a mutable column. The prototype looked this
    // up by email, which is exactly why its RLS policies could not be written.
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      setState(() {
        _tipoUsuario = null;
        _loading = false;
      });
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('usuario')
          .select('papel')
          .eq('id', userId)
          .maybeSingle();

      setState(() {
        _tipoUsuario = data?['papel'];
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

    // Redireciona conforme o papel. Os valores são identificadores em minúsculas
    // sem acento, definidos pelo CHECK em usuario.papel — nunca rótulos de tela.
    if (_tipoUsuario == 'tecnico') {
      return const HomeTecnicoPage();
    } else if (_tipoUsuario == 'supervisor') {
      return const HomeSupervisor();
    } else if (_tipoUsuario == 'suporte') {
      return const HomeSuporte();
    }

    // Caso o usuário não esteja na tabela 'usuarios' ou não tenha tipo definido
    return Scaffold(
      appBar: AppBar(title: const Text('Acesso')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Usuário sem papel definido em "usuario".'),
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
