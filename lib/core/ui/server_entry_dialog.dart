import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_exception.dart';
import '../../features/servers/invite_link_parser.dart';
import '../../features/servers/servers_providers.dart';
import 'buttons/app_segmented_control.dart';
import 'ds_tokens.dart';
import 'inputs/app_text_field.dart';
import 'overlays/app_modal_window.dart';

/// Abre o modal de criar/entrar em servidor (mesmo padrão visual de
/// [showMacModalWindow]/`showSettingsModal`: blur, ESC fecha, dismiss fora).
///
/// Substitui a antiga página `/create-server` com paridade exata de
/// recursos: modo criar (nome → `POST /servers`) e modo entrar (link/código
/// → `POST /invites/:code/accept`). Em ambos, o modal fecha e navega para
/// o shell do servidor.
Future<void> showServerEntryDialog(BuildContext context) {
  return showMacModalWindow(
    context: context,
    title: 'Criar ou entrar em um servidor',
    maxWidth: 520,
    child: const ServerEntryDialog(),
  );
}

/// Modo do dialog: criar um servidor novo ou entrar em um existente via
/// convite (estilo Discord: o mesmo gesto "＋" oferece as duas opções).
enum ServerEntryMode { create, join }

/// Conteúdo do modal — lógica extraída da antiga `CreateServerScreen`.
class ServerEntryDialog extends ConsumerStatefulWidget {
  const ServerEntryDialog({super.key});

  @override
  ConsumerState<ServerEntryDialog> createState() => _ServerEntryDialogState();
}

class _ServerEntryDialogState extends ConsumerState<ServerEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _inviteLinkController = TextEditingController();
  ServerEntryMode _mode = ServerEntryMode.create;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _inviteLinkController.dispose();
    super.dispose();
  }

  void _switchMode(ServerEntryMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  /// Fecha o modal e navega para o servidor. O [GoRouter] é capturado antes
  /// do `pop` porque o [BuildContext] do dialog é desativado ao fechar.
  void _goToServer(String serverId) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/servers/$serverId');
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
      _goToServer(server.id);
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
      _goToServer(serverId);
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
    final isCreate = _mode == ServerEntryMode.create;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSegmentedControl<ServerEntryMode>(
              height: 38,
              items: const [
                SegmentItem(
                  value: ServerEntryMode.create,
                  label: 'Criar',
                  icon: Icons.add,
                ),
                SegmentItem(
                  value: ServerEntryMode.join,
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
              isCreate ? 'Crie sua comunidade' : 'Entre em uma comunidade',
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
                validator: (value) => (value == null || value.trim().isEmpty)
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      isCreate ? 'Criar servidor' : 'Entrar no servidor',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
