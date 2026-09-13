import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ui/ui.dart';

/// Tela exibida enquanto o AuthState é desconhecido (bootstrap da sessão).
///
/// O redirect do router (§7.2) mostra esta tela até o
/// [AuthController] terminar de validar os tokens.
///
/// Animação de loading da logo: flutuação + "squish" suave na logo
/// (via [Transform], sem relayout), órbita de 3 pontinhos nas cores
/// da marca (via [_SplashOrbitPainter] com `repaint: animation`,
/// sem rebuild de widgets) e fileirinha de dots com pulo escalonado.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_FloatingLogo(), SizedBox(height: 28), _BouncingDots()],
        ),
      ),
    );
  }
}

/// Logo flutuando (translateY ±6px) com leve "squish" + balanço,
/// orbitada por 3 dots pintados em canvas.
///
/// A logo estática vai em [AnimatedBuilder.child] para não reconstruir
/// o `Image.asset` a cada frame — só os [Transform] (compositing)
/// são refeitos, sem relayout.
class _FloatingLogo extends StatelessWidget {
  const _FloatingLogo();

  static const _logoSize = 64.0;
  static const _orbitSize = 128.0;

  @override
  Widget build(BuildContext context) {
    final controller =
        (context.findAncestorStateOfType<_SplashScreenState>())!._controller;
    return SizedBox(
      width: _orbitSize,
      height: _orbitSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: const Size.square(_orbitSize),
              painter: _SplashOrbitPainter(animation: controller),
            ),
          ),
          AnimatedBuilder(
            animation: controller,
            child: const AppLogo(size: _logoSize),
            builder: (context, child) {
              final t = controller.value * math.pi * 2;
              final dy = math.sin(t) * 6.0;
              final scale = 1.0 + math.sin(t * 2) * 0.045;
              final wobble = math.sin(t) * 0.06;
              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform.rotate(
                  angle: wobble,
                  child: Transform.scale(
                    scaleX: scale,
                    // Squish: quando larga, achata (e vice-versa).
                    scaleY: 2 - scale,
                    child: child,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Anel + 3 dots orbitando a logo + anel pulsante.
///
/// Usa `super(repaint: animation)`: repinta direto no raster a cada
/// tick do vsync sem passar por build/layout. Só fills e strokes
/// simples — sem blur/saveLayer/shadow.
class _SplashOrbitPainter extends CustomPainter {
  _SplashOrbitPainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  static const _orbitColors = [
    AppTokens.accentVercel,
    AppTokens.accentPurple,
    AppTokens.accentAmber,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final t = animation.value;
    final orbitRadius = size.width / 2 - 6;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(center, orbitRadius, ringPaint);

    // Anel pulsante: expande e some, em loop.
    final pulse = t; // 0 → 1
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppTokens.accentPurple.withValues(alpha: (1 - pulse) * 0.35);
    canvas.drawCircle(center, orbitRadius - 10 + pulse * 10, pulsePaint);

    for (var i = 0; i < 3; i++) {
      final angle = t * math.pi * 2 + i * (math.pi * 2 / 3);
      final dotCenter = Offset(
        center.dx + math.cos(angle) * orbitRadius,
        center.dy + math.sin(angle) * orbitRadius,
      );
      // Dot da "frente" (seno > 0) cresce um pouco — pseudo-profundidade.
      final r = 4.0 + (math.sin(angle) * 0.5 + 0.5) * 2.0;
      canvas.drawCircle(dotCenter, r, Paint()..color = _orbitColors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashOrbitPainter oldDelegate) => false;
}

/// Fileirinha de 3 dots pulando em sequência (intervalos escalonados
/// sobre o mesmo controller — um único ticker para o splash todo).
class _BouncingDots extends StatelessWidget {
  const _BouncingDots();

  @override
  Widget build(BuildContext context) {
    final controller =
        (context.findAncestorStateOfType<_SplashScreenState>())!._controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Cada dot ocupa uma fatia de 1/3 do ciclo, com sobra p/ o pulo.
            final local = ((controller.value * 3 - i * 0.5) % 1.0 + 1.0) % 1.0;
            final jump = local < 0.5 ? math.sin(local * math.pi) : 0.0;
            return Transform.translate(
              offset: Offset(0, -jump * 7),
              child: Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.35 + jump * 0.65),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
