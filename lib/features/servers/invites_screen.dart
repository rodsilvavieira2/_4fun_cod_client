import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Criação de convite por OWNER/ADMIN com URL copiável.
class InvitesScreen extends ConsumerStatefulWidget {
  const InvitesScreen({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  bool _creating = false;
  String? _error;
  InviteInfo? _invite;

  Future<void> _createInvite() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final invite = await ref
          .read(serverDetailProvider(widget.serverId).notifier)
          .createInvite();
      if (mounted) setState(() => _invite = invite);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _copy() async {
    final invite = _invite;
    if (invite == null) return;
    await Clipboard.setData(ClipboardData(text: invite.url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Convite copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(serverDetailProvider(widget.serverId));
    final canManageServer = detail.valueOrNull?.canManageServer ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Convites')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Tentar novamente',
              onPressed: () =>
                  ref.invalidate(serverDetailProvider(widget.serverId)),
            ),
          ),
          data: (_) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: !canManageServer
                    ? const Text('Apenas administradores podem criar convites.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: _creating ? null : _createInvite,
                            icon: _creating
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.link),
                            label: const Text('Criar convite'),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          if (_invite != null) ...[
                            const SizedBox(height: 24),
                            _InviteCard(invite: _invite!, onCopy: _copy),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite, required this.onCopy});

  final InviteInfo invite;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Convite criado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(invite.url),
            const SizedBox(height: 12),
            Text(
              'Código: ${invite.code}'
              '${invite.maxUses != null ? ' · Máx. usos: ${invite.maxUses}' : ''}'
              '${invite.expiresAt != null ? ' · Expira: ${_formatDate(invite.expiresAt!)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy),
              label: const Text('Copiar link'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
