import 'package:flutter/material.dart';

class HomeSupervisor extends StatelessWidget {
  const HomeSupervisor({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supervisor')),
      body: const Center(child: Text('Bem-vindo, Supervisor!')),
    );
  }
}
