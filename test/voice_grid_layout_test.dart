import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/features/voice/voice_screen.dart';

void main() {
  group('calculateVoiceGridGeometry', () {
    test('coloca duas publicações lado a lado em uma janela horizontal', () {
      final geometry = calculateVoiceGridGeometry(
        viewport: const Size(1000, 500),
        tileCount: 2,
      );

      expect(geometry.columns, 2);
      expect(geometry.rows, 1);
    });

    test('usa grade 2x2 para três publicações sem deformar os tiles', () {
      final geometry = calculateVoiceGridGeometry(
        viewport: const Size(1000, 500),
        tileCount: 3,
      );

      expect(geometry.columns, 2);
      expect(geometry.rows, 2);
      expect(
        geometry.tileSize.width / geometry.tileSize.height,
        closeTo(16 / 9, 0.001),
      );
    });

    test('acomoda câmera e tela de seis fontes sem sair do viewport', () {
      // Área útil de uma janela 1200x700 depois do header/dock da chamada.
      const viewport = Size(1200, 580);
      final geometry = calculateVoiceGridGeometry(
        viewport: viewport,
        tileCount: 6,
      );

      expect(geometry.columns, 3);
      expect(geometry.rows, 2);
      expect(geometry.gridSize.width, lessThanOrEqualTo(viewport.width));
      expect(geometry.gridSize.height, lessThanOrEqualTo(viewport.height));
    });
  });
}
