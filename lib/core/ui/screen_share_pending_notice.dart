import 'package:flutter/material.dart';

import '../theme/appearance_theme.dart';

/// Wrap mantém o cancelamento acessível até no rodapé estreito da sidebar.
class ScreenSharePendingNotice extends StatelessWidget {
  const ScreenSharePendingNotice({
    super.key,
    required this.waiting,
    required this.onCancel,
  });
  final bool waiting;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Material(
    color: context.appColors.surface2,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              waiting ? 'guardando voltar a janela' : 'Iniciando transmissão…',
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancelar')),
        ],
      ),
    ),
  );
}
