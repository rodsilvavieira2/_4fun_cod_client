import 'package:flutter/material.dart';

/// Logotipo oficial do 4FunCode.
///
/// Usa o ícone do app (`assets/branding/app_logo.png`) com cantos
/// arredondados, em qualquer superfície dentro do produto
/// (login, cadastro, splash, home).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44, this.radiusFactor = 0.28});

  final double size;

  /// Fração de [size] usada como raio da borda.
  final double radiusFactor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * radiusFactor),
      child: Image.asset(
        'assets/branding/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
