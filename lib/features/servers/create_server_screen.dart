import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/ui/ui.dart';
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
      final server = await ref
          .read(serversProvider.notifier)
          .create(_nameController.text.trim());
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
      final serverId = await ref
          .read(serversRepositoryProvider)
          .acceptInvite(code);
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
      appBar: AppBar(title: const Text('Criar ou entrar em um servidor')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: AppCard(
                padding: const EdgeInsets.all(28),
                backgroundColor: AppTokens.surface1,
                borderColor: AppTokens.borderStrong,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSegmentedControl<_ServerEntryMode>(
                        height: 38,
                        items: const [
                          SegmentItem(
                            value: _ServerEntryMode.create,
                            label: 'Criar',
                            icon: Icons.add,
                          ),
                          SegmentItem(
                            value: _ServerEntryMode.join,
                            label: 'Entrar',
                            icon: Icons.group_add_outlined,
                          ),
                        ],
                        selectedValue: _mode,
                        onChanged: _switchMode,
                      ),
                      const SizedBox(height: 28),
                      Align(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            color: AppTokens.surface2,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCreate
                                ? Icons.groups_2_outlined
                                : Icons.group_add_outlined,
                            size: 28,
                            color: AppTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isCreate
                            ? 'Crie sua comunidade'
                            : 'Entre em uma comunidade',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        isCreate
                            ? 'Dê um nome ao espaço onde sua galera vai conversar.'
                            : 'Cole o link do convite ou apenas o código.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13.5,
                          height: 1.45,
                          color: AppTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (isCreate)
                        AppTextField(
                          controller: _nameController,
                          autofocus: !kIsWeb,
                          label: 'NOME DO SERVIDOR',
                          hintText: 'Minha comunidade',
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Informe o nome do servidor.'
                              : null,
                          onFieldSubmitted: (_) => _create(),
                        )
                      else
                        AppTextField(
                          controller: _inviteLinkController,
                          autofocus: !kIsWeb,
                          label: 'LINK OU CÓDIGO DO CONVITE',
                          hintText: 'https://…/invite/CodigoDoConvite',
                          validator: (value) =>
                              extractInviteCode(value ?? '') == null
                              ? 'Cole um link de convite válido.'
                              : null,
                          onFieldSubmitted: (_) => _join(),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12.5,
                            color: AppTokens.accentPurple,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : (isCreate ? _create : _join),
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isCreate
                                    ? 'Criar servidor'
                                    : 'Entrar no servidor',
                              ),
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
