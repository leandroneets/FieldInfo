import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'semeadura_form_tecnico.dart';
import 'plano_list_tecnico.dart';


/// --- Screen palette overrides ---
const Color kFabBlue  = Color(0xFF0D47A1); // Dark blue for FAB
const Color kMenuBlue = Color(0xFF1E88E5); // Softer blue for menu items
/// ---------------------------------

class HomeTecnicoPage extends StatefulWidget {
  const HomeTecnicoPage({super.key});

  @override
  State<HomeTecnicoPage> createState() => _HomeTecnicoPageState();
}

class _HomeTecnicoPageState extends State<HomeTecnicoPage>
    with SingleTickerProviderStateMixin {
  bool isMenuOpen = false;

  late final AnimationController _ctrl;      // controla todas as animações
  late final Animation<double> _rotateFab;   // rotação do FAB (botão todo)
  late final Animation<Offset> _slide;       // slide sutil do menu

  // Medidas para alinhamento
  static const _fabMargin = 16.0;  // margem lateral/inferior padrão do FAB
  static const _gapMenuFab = 25.0; // espaço entre topo do FAB e a caixa do menu
  static const _fabSize = 56.0;    // tamanho padrão do FAB (sem scale)
  static const _fabScale = 1.1;    // 10% maior

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _rotateFab = Tween<double>(begin: 0.0, end: 0.25).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      isMenuOpen = !isMenuOpen;
      if (isMenuOpen) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    });
  }

  void _closeMenu() {
    if (!isMenuOpen) return;
    setState(() {
      isMenuOpen = false;
      _ctrl.reverse();
    });
  }

  double get _fabVisualHeight => _fabSize * _fabScale; // ~61.6 px

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kFabBlue,              // mesma cor do FAB
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: kFabBlue,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: const Text(
          'FieldInfo — Técnico',
          style: TextStyle(
            color: Colors.white,                // texto branco no AppBar
            fontWeight: FontWeight.w600,
          ),
        ),
        foregroundColor: Colors.white,          // ícones/voltar em branco
      ),

      body: Stack(
        children: [
          // Conteúdo base
          const Center(child: Text('Bem-vindo!')),

          // Overlay escuro clicável para fechar tocando fora
          if (isMenuOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMenu,
                child: Container(color: Colors.black.withOpacity(0.25)),
              ),
            ),

          // Caixa do menu (alinhada acima do FAB à esquerda) com fade + slide
          Positioned(
            left: _fabMargin,
            // Coloca a caixa imediatamente acima do FAB, somando um gap
            bottom: _fabMargin + _fabVisualHeight + _gapMenuFab,
            child: IgnorePointer(
              ignoring: !isMenuOpen, // bloqueia cliques quando fechado
              child: FadeTransition(
                opacity: _ctrl,
                child: SlideTransition(
                  position: _slide,
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context).colorScheme.surface,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 260,
                        maxWidth: 320,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 10,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:  [
                            _MenuItem(icon: Icons.map_outlined,     text: 'Campos', onTap: () {
                              _closeMenu();
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const PlanoListTecnico()),
                              );
                            },),
                            Divider(height: 6),
                            _MenuItem(icon: Icons.agriculture,      text: 'Semeadura', onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SemeaduraFormTecnico()),
                              );
                            },),
                            Divider(height: 6),
                            _MenuItem(icon: Icons.checklist,        text: 'CheckList BioEnsaio'),
                            Divider(height: 6),
                            _MenuItem(icon: Icons.science_outlined, text: 'Bioensaio'),
                            Divider(height: 6),
                            _MenuItem(icon: Icons.eco_outlined,     text: 'Estádio Fenológico'),
                            Divider(height: 6),
                            _MenuItem(icon: Icons.grass,            text: 'Colheita'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // FAB no canto inferior esquerdo com rotação do botão inteiro
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: RotationTransition(
        turns: _rotateFab, // gira o BOTÃO
        child: Transform.scale(
          scale: _fabScale, // 10% maior
          child: FloatingActionButton(
            backgroundColor: kFabBlue,
            foregroundColor: Colors.white, // garante ícone em branco
            onPressed: _toggleMenu,
            child: AnimatedIcon(
              icon: AnimatedIcons.menu_close,
              progress: _ctrl,
              size: 30,
              color: Colors.white, // reforço: ícone branco
            ),
          ),
        ),
      ),
    );
  }
}

/// Item do menu (apenas UI; por enquanto sem navegação)
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  const _MenuItem({
    super.key,
    required this.icon,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Clicou em "$text"')),
            );
          },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: kMenuBlue),
            const SizedBox(width: 10),
            Text(text, style: const TextStyle(fontSize: 16, color: kMenuBlue)),
          ],
        ),
      ),
    );
  }
}
