import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voice/share_link_providers.dart';
import 'app_icon.dart';
import 'overlays/app_modal_window.dart';

/// Abre o modal do link de transmissão (mesmo padrão visual de
/// [showInviteDialog]: blur, ESC fecha, dismiss fora).
///
/// Só faz sentido com share ativo — o link expira quando a transmissão
/// termina. Quem abre é o tile local / menu `⋯` do theater.
Future<void> showShareLinkDialog(
  BuildContext context, {
  required String serverId,
  required String channelId,
}) {
  return showMacModalWindow(
    context: context,
    title: 'Link da transmissão',
    maxWidth: 480,
    child: ShareLinkDialog(serverId: serverId, channelId: channelId),
  );
}

/// Conteúdo do modal: criar → card copiável → encerrar. Erro nunca afeta a
/// sessão de voz (o share segue no ar mesmo se o link falhar).
class ShareLinkDialog extends ConsumerWidget {
  const ShareLinkDialog({
    super.key,
    required this.serverId,
    required this.channelId,
  });

  final String serverId;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = (serverId: serverId, channelId: channelId);
    final state = ref.watch(screenShareLinkProvider(arg));
    final notifier = ref.read(screenShareLinkProvider(arg).notifier);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switch (state.status) {
            ShareLinkStatus.idle => FilledButton.icon(
              onPressed: notifier.createLink,
              icon: AppIcon(AppIcons.link),
              label: const Text('Criar link de transmissão'),
            ),
            ShareLinkStatus.creating => const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            ShareLinkStatus.error => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state.errorMessage ?? 'Erro inesperado. Tente novamente.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: notifier.createLink,
                  icon: AppIcon(AppIcons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
            ShareLinkStatus.ready => _ShareLinkCard(
              arg: arg,
              onRevoke: notifier.revokeActive,
            ),
          },
        ],
      ),
    );
  }
}

class _ShareLinkCard extends ConsumerWidget {
  const _ShareLinkCard({required this.arg, required this.onRevoke});

  final ({String serverId, String channelId}) arg;
  final VoidCallback onRevoke;

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final url = ref.read(screenShareLinkProvider(arg)).link?.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copiado.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(screenShareLinkProvider(arg)).link;
    if (link == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Qualquer pessoa com o link assiste no browser',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(link.url),
            const SizedBox(height: 8),
            Text(
              'O link expira automaticamente quando a transmissão terminar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _copy(context, ref),
              icon: AppIcon(AppIcons.copy),
              label: const Text('Copiar link'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRevoke,
              icon: AppIcon(AppIcons.unlink),
              label: const Text('Encerrar link'),
            ),
          ],
        ),
      ),
    );
  }
}
