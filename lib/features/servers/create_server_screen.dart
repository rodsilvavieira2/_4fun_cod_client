import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import 'invite_link_parser.dart';
import 'servers_providers.dart';

/// Modo da tela: criar um servidor novo ou entrar em um existente via
/// convite (estilo Discord: o mesmo gesto "＋" oferece as duas opções).
enum _ServerEntryMode { create, join }

/// Tela de entrada em servidor: criar (nome → `POST /servers`) ou entrar
/// (colar link/código de convite → `POST /invites/:code/accept`). Navega
/// para o shell do servidor em ambos os casos.
class CreateServerScreen extends ConsumerStatefulWidget {
  const CreateServerScreen({super.key});

  @override
  ConsumerState<CreateServerScreen> createState() => _CreateServerScreenState();
}

class _CreateServerScreenState extends ConsumerState<CreateServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _inviteLinkController = TextEditingController();
  _ServerEntryMode _mode = _ServerEntryMode.create;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _inviteLinkController.dispose();
    super.dispose();
  }

  void _switchMode(_ServerEntryMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _create() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final server =
          await ref.read(serversProvider.notifier).create(_nameController.text.trim());
      if (!mounted) return;
      context.go('/servers/${server.id}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final code = extractInviteCode(_inviteLinkController.text);
    if (code == null) return; // o validator já cobre; defesa extra
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final serverId =
          await ref.read(serversRepositoryProvider).acceptInvite(code);
      ref.invalidate(serversProvider);
      if (!mounted) return;
      context.go('/servers/$serverId');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = _mode == _ServerEntryMode.create;
    return Scaffold(
      appBar: AppBar(title: const Text('Servidores')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<_ServerEntryMode>(
                      segments: const [
                        ButtonSegment(
                          value: _ServerEntryMode.create,
                          label: Text('Criar'),
                          icon: Icon(Icons.add),
                        ),
                        ButtonSegment(
                          value: _ServerEntryMode.join,
                          label: Text('Entrar em um servidor'),
                          icon: Icon(Icons.group_add_outlined),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (selection) =>
                          _switchMode(selection.first),
                    ),
                    const SizedBox(height: 32),
                    if (isCreate) ...[
                      const Icon(Icons.dns_outlined, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Dê um nome ao seu servidor',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameController,
                        autofocus: !kIsWeb,
                        decoration: const InputDecoration(
                          labelText: 'Nome do servidor',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Informe o nome do servidor.'
                                : null,
                        onFieldSubmitted: (_) => _create(),
                      ),
                    ] else ...[
                      const Icon(Icons.group_add_outlined, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Entre com um convite',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cole o link do convite (ou apenas o código).',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _inviteLinkController,
                        autofocus: !kIsWeb,
                        decoration: const InputDecoration(
                          labelText: 'Link do convite',
                          hintText: 'https://…/invite/CodigoDoConvite',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            extractInviteCode(value ?? '') == null
                                ? 'Cole um link de convite válido.'
                                : null,
                        onFieldSubmitted: (_) => _join(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : (isCreate ? _create : _join),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isCreate ? 'Criar servidor' : 'Entrar no servidor'),
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
