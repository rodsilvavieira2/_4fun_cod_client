import 'package:flutter/material.dart';

import '../theme/appearance_theme.dart';
import 'app_file_image.dart';

/// Ângulo dourado para distribuir matizes de acento (mesma fórmula usada na
/// lista de canais para ocupantes de voz — mantém identidade visual estável
/// por participante entre header do teatro e sidebar).
const _voiceAvatarGoldenAngle = 137.50776405003785;

/// Cor de acento estável para um participante (anel de fala).
Color voiceAvatarAccent(String seed) {
  final hash = _stableVoiceAvatarHash(seed);
  final hue = ((hash % 1024) * _voiceAvatarGoldenAngle) % 360;
  return HSVColor.fromAHSV(1, hue, 0.42, 0.76).toColor();
}

int _stableVoiceAvatarHash(String value) {
  const fnvPrime = 0x01000193;
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Avatar circular de participante de voz.
///
/// Mostra a foto de perfil (`User.avatarUrl`, via [AppFileImage] autenticado)
/// quando houver; sem foto (nulo/vazio/erro/loading) mantém a inicial — mesmo
/// contrato do fallback já usado na lista de canais e no chat.
///
/// O anel de fala (`speaking`) troca a borda neutra `surface1` pelo acento do
/// participante, espelhando o comportamento do `_VoiceOccupantAvatar`.
class ParticipantAvatar extends StatelessWidget {
  const ParticipantAvatar({
    super.key,
    required this.displayName,
    this.avatarUrl,
    this.radius = 11,
    this.speaking = false,
    this.accent,
  });

  /// Nome de exibição (base da inicial de fallback).
  final String displayName;

  /// Path relativo (`/api/v1/files/...`) ou URL absoluta. Nulo = inicial.
  final String? avatarUrl;

  final double radius;

  final bool speaking;

  /// Acento do anel de fala. Nulo = derivado de [displayName].
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final initial = displayName.isEmpty
        ? '?'
        : displayName[0].toUpperCase();
    final effectiveAccent = accent ?? voiceAvatarAccent(displayName);
    final diameter = radius * 2;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.activeOverlay,
        border: Border.all(
          color: speaking
              ? effectiveAccent.withValues(alpha: 0.9)
              : colors.surface1,
          width: speaking ? 1.5 : 2,
        ),
        boxShadow: [
          if (speaking)
            BoxShadow(
              color: effectiveAccent.withValues(alpha: 0.35),
              blurRadius: 8,
              spreadRadius: -2,
            ),
        ],
      ),
      child: ClipOval(
        child: AppFileImage(
          path: avatarUrl,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          fallback: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: radius * 0.9,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
