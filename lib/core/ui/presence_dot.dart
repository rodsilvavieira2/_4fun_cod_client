import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Indicador visual de presença ao lado do nome (dot verde = online,
/// cinza = offline; cores oficiais do tema v3).
class PresenceDot extends StatelessWidget {
  const PresenceDot({super.key, required this.online, this.size = 10});

  final bool online;

  /// Diâmetro do dot (default 10).
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: online ? 'Online' : 'Offline',
      child: Icon(
        Icons.circle,
        size: size,
        color: online ? AppStatusColors.online : AppStatusColors.offline,
      ),
    );
  }
}
