import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import 'servers_providers.dart';

/// Deep link público `/invite/:code`: resolve o convite (sem login) e
/// oferece aceitar (exige sessão; deslogado → /login preservando o retorno).
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  bool _accepting = false;
  String? _error;

  Future<void> _accept() async {
    if (_accepting) return;
    // Aceitar exige sessão: deslogado → login com retorno para este convite.
    final authState = ref.read(authControllerProvider).valueOrNull;
    if (authState is! Authenticated) {
      context.push('/login?redirect=/invite/${widget.code}');
      return;
    }
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await ref.read(serversRepositoryProvider).acceptInvite(widget.code);
      ref.invalidate(serversProvider);
      final detail = ref.read(inviteDetailProvider(widget.code)).valueOrNull;
      if (!mounted) return;
      if (detail != null) {
        context.go('/servers/${detail.server.id}');
      } else {
        context.go('/');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(inviteDetailProvider(widget.code));
    return Scaffold(
      appBar: AppBar(title: const Text('Convite')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: detail.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error is ApiException
                          ? error.message
                          : 'Não foi possível carregar o convite.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () =>
                          ref.invalidate(inviteDetailProvider(widget.code)),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
                data: (data) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      foregroundImage: data.server.iconUrl != null
                          ? NetworkImage(data.server.iconUrl!)
                          : null,
                      child: data.server.iconUrl == null
                          ? const Icon(Icons.dns_outlined, size: 40)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      data.server.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${data.server.memberCount} '
                      '${data.server.memberCount == 1 ? 'membro' : 'membros'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _accepting ? null : _accept,
                      icon: _accepting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Aceitar convite'),
                    ),
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
