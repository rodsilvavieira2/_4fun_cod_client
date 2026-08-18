import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../channels/channels_providers.dart';
import 'servers_providers.dart';

/// Configurações do servidor: nome, ícone, excluir (OWNER) ou sair
/// (não-OWNER).
class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _iconController = TextEditingController();
  bool _saving = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final detail = ref.read(serverDetailProvider(widget.serverId)).valueOrNull;
    _nameController.text = detail?.server.name ?? '';
    _iconController.text = detail?.server.iconUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(serverDetailProvider(widget.serverId).notifier);
      final name = _nameController.text.trim();
      final iconUrl = _iconController.text.trim();
      if (name != ref.read(serverDetailProvider(widget.serverId)).valueOrNull?.server.name) {
        await notifier.updateName(name);
      }
      if (iconUrl.isNotEmpty &&
          iconUrl != ref.read(serverDetailProvider(widget.serverId)).valueOrNull?.server.iconUrl) {
        await notifier.updateIcon(iconUrl);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servidor atualizado.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir servidor'),
        content: const Text(
          'Todos os canais e mensagens serão perdidos. Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(serverDetailProvider(widget.serverId).notifier).delete();
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair do servidor'),
        content: const Text('Você não fará mais parte deste servidor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(serversProvider.notifier).leave(widget.serverId);
      // Limpa caches do servidor deixado (detail + canais) para não ficarem
      // stale se o usuário revisitar via convite.
      ref.invalidate(serverDetailProvider(widget.serverId));
      ref.invalidate(channelsControllerProvider(widget.serverId));
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(serverDetailProvider(widget.serverId));
    final isOwner = detail.valueOrNull?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do servidor')),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Informações',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do servidor',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Informe o nome do servidor.'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _iconController,
                        decoration: const InputDecoration(
                          labelText: 'URL do ícone',
                          border: OutlineInputBorder(),
                        ),
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
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _saving || _working ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Salvar'),
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (isOwner)
                        OutlinedButton.icon(
                          onPressed: _working ? null : _delete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Excluir servidor'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _working ? null : _leave,
                          icon: const Icon(Icons.logout),
                          label: const Text('Sair do servidor'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
