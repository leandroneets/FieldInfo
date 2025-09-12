import 'package:flutter/material.dart';
import 'create_user.dart';
import 'create_plano.dart';
import 'assign_plano.dart' ; // topo do arquivo



class HomeSuporte extends StatelessWidget {
  const HomeSuporte({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suporte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Optional: implement logout
              Navigator.pop(context);
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              'Bem-vindo, Suporte!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Criar Novo Usuário'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CreateUserPage()),
                );
              },
            )
            
            
            ,
            const SizedBox(height: 10),

            ElevatedButton.icon(
  icon: const Icon(Icons.add_chart),
  label: const Text('Criar Plano de Produção'),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreatePlanoPage()),
    );
  },
),

const SizedBox(height: 10),
ElevatedButton.icon(
  icon: const Icon(Icons.link),
  label: const Text('Atribuir Plano a Técnico'),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AssignPlanoPage()),
    );
  },
),


            // Future buttons:
            // ElevatedButton.icon(...), // Criar Plano de Produção
            // ElevatedButton.icon(...), // Registrar Safra
            // ElevatedButton.icon(...), // Registrar Material
          ],
        ),
      ),
    );
  }
}
