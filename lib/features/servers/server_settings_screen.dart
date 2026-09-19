import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import '../channels/channels_providers.dart';
import 'servers_providers.dart';

/// Standalone host for the server administration content.
///
/// The app's regular entry point uses the dedicated server settings modal;
/// this host keeps the content reusable without weakening its role check.
class ServerSettingsScreen extends StatelessWidget {
  const ServerSettingsScreen({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do servidor')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ServerSettingsContent(
              serverId: serverId,
              onOpenMembers: () => context.push('/servers/$serverId/members'),
              onServerExited: () => context.go('/'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable administration content shared by the direct route and the modal.
///
/// Access is checked here as well as at each UI entry point. The API remains
/// the final authority for every mutation.
class ServerSettingsContent extends ConsumerStatefulWidget {
  const ServerSettingsContent({
    super.key,
    required this.serverId,
    required this.onOpenMembers,
    required this.onServerExited,
  });

  final String serverId;
  final VoidCallback onOpenMembers;
  final VoidCallback onServerExited;

  @override
  ConsumerState<ServerSettingsContent> createState() =>
      _ServerSettingsContentState();
}

class _ServerSettingsContentState extends ConsumerState<ServerSettingsContent> {
  static const _imageTypeGroup = XTypeGroup(
    label: 'Imagens',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
  );
  static const _maxImageBytes = 5 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _savingIcon = false;
  List<int>? _previewIconBytes;
  bool _working = false;
  String? _savedName;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServerSettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId == widget.serverId) return;
    _initialized = false;
    _savedName = null;
    _error = null;
    _nameController.clear();
  }

  void _initializeForm(ServerDetail detail) {
    if (_initialized) return;
    _initialized = true;
    _savedName = detail.server.name;
    _nameController.text = detail.server.name;
  }

  Future<void> _save() async {
    if (_saving ||
        _savingIcon ||
        _working ||
        !_formKey.currentState!.validate()) {
      return;
    }
    final name = _nameController.text.trim();
    if (name == _savedName) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(serverDetailProvider(widget.serverId).notifier)
          .updateName(name);
      _savedName = name;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Servidor atualizado.')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erro inesperado. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickIcon() async {
    if (_savingIcon || _saving || _working) return;
    final file = await openFile(acceptedTypeGroups: const [_imageTypeGroup]);
    if (file == null || !mounted) return;

    final contentType = _contentTypeFor(file.name);
    if (contentType == null) {
      setState(() => _error = 'Formato de imagem não suportado.');
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxImageBytes) {
      setState(() => _error = 'A imagem deve ter no máximo 5 MB.');
      return;
    }

    setState(() {
      _savingIcon = true;
      _previewIconBytes = bytes;
      _error = null;
    });
    try {
      await ref
          .read(serverDetailProvider(widget.serverId).notifier)
          .uploadIcon(
            bytes: bytes,
            fileName: file.name,
            contentType: contentType,
          );
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _previewIconBytes = null;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewIconBytes = null;
          _error = 'Falha ao enviar a imagem. Tente novamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingIcon = false;
          _previewIconBytes = null;
        });
      }
    }
  }

  Future<void> _removeIcon() async {
    if (_savingIcon || _saving || _working) return;
    setState(() {
      _savingIcon = true;
      _error = null;
    });
    try {
      await ref
          .read(serverDetailProvider(widget.serverId).notifier)
          .removeIcon();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível remover o ícone.');
      }
    } finally {
      if (mounted) setState(() => _savingIcon = false);
    }
  }

  Future<void> _delete() async {
    if (_working || _saving || _savingIcon) return;
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(serverDetailProvider(widget.serverId).notifier).delete();
      if (mounted) widget.onServerExited();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erro inesperado. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _leave() async {
    if (_working || _saving || _savingIcon) return;
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(serversProvider.notifier).leave(widget.serverId);
      ref.invalidate(serverDetailProvider(widget.serverId));
      ref.invalidate(channelsControllerProvider(widget.serverId));
      if (mounted) widget.onServerExited();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erro inesperado. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(serverDetailProvider(widget.serverId));
    return detail.when(
      skipLoadingOnRefresh: false,
      loading: () => const _ServerSettingsStatus(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, _) => _ServerSettingsStatus(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Não foi possível carregar as configurações.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(serverDetailProvider(widget.serverId)),
              icon: AppIcon(AppIcons.refresh, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
      data: (detail) {
        if (!detail.canManageServer) {
          return _ServerSettingsStatus(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.lock, size: 30, color: AppTokens.textMuted),
                SizedBox(height: 12),
                Text(
                  'Apenas administradores podem acessar as configurações do servidor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTokens.textSecondary),
                ),
              ],
            ),
          );
        }

        _initializeForm(detail);
        return _buildForm(detail);
      },
    );
  }

  Widget _buildForm(ServerDetail detail) {
    final currentRole = detail.myRole ?? ServerRole.member;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final roleSummary = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Administração',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ServerRoleBadge(role: currentRole),
                      const SizedBox(height: 8),
                      Text(
                        currentRole.description,
                        style: const TextStyle(
                          color: AppTokens.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  );
                  final membersButton = OutlinedButton.icon(
                    onPressed: _working || _saving || _savingIcon
                        ? null
                        : widget.onOpenMembers,
                    icon: AppIcon(AppIcons.userSettings, size: 17),
                    label: const Text('Membros e cargos'),
                  );

                  if (constraints.maxWidth < 360) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        roleSummary,
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: membersButton,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: roleSummary),
                      const SizedBox(width: 12),
                      membersButton,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader('INFORMAÇÕES DO SERVIDOR'),
            const SizedBox(height: 10),
            _ServerIconEditor(
              server: detail.server,
              loading: _savingIcon,
              enabled: !_saving && !_working,
              previewBytes: _previewIconBytes,
              onPick: _pickIcon,
              onRemove: _removeIcon,
            ),
            const SizedBox(height: 18),
            AppTextField(
              key: const Key('server-settings-name'),
              controller: _nameController,
              label: 'Nome do servidor',
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe o nome do servidor.'
                  : null,
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppTokens.accentDanger,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Salvar alterações',
                onPressed: _saving || _savingIcon || _working ? null : _save,
                loading: _saving,
              ),
            ),
            const SizedBox(height: 28),
            const Divider(height: 1, color: AppTokens.borderHairline),
            const SizedBox(height: 20),
            Text(
              currentRole.isOwner ? 'ZONA DE PERIGO' : 'SAIR DO SERVIDOR',
              style: const TextStyle(
                fontFamily: 'Geist Mono',
                fontSize: 10.5,
                color: AppTokens.textMuted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: currentRole.isOwner
                    ? 'Excluir servidor'
                    : 'Sair do servidor',
                icon: currentRole.isOwner ? AppIcons.delete : AppIcons.logout,
                variant: AppButtonVariant.danger,
                onPressed: _working || _saving || _savingIcon
                    ? null
                    : (currentRole.isOwner ? _delete : _leave),
                loading: _working,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerSettingsStatus extends StatelessWidget {
  const _ServerSettingsStatus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 280),
      child: Center(
        child: Padding(padding: const EdgeInsets.all(32), child: child),
      ),
    );
  }
}

class _ServerIconEditor extends StatelessWidget {
  const _ServerIconEditor({
    required this.server,
    required this.loading,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
    this.previewBytes,
  });

  final Server server;
  final bool loading;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  /// Preview local otimista (bytes recém-escolhidos, antes do `READY`).
  final List<int>? previewBytes;

  @override
  Widget build(BuildContext context) {
    final iconUrl = server.iconUrl;
    final preview = previewBytes;
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 58,
          height: 58,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTokens.surface3,
            shape: BoxShape.circle,
            border: Border.all(color: AppTokens.borderSubtle),
          ),
          child: preview != null
              ? Image.memory(
                  Uint8List.fromList(preview),
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => AppIcon(
                    AppIcons.server,
                    color: AppTokens.textMuted,
                  ),
                )
              : iconUrl == null
              ? Text(
                  server.name.isEmpty ? '?' : server.name[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                  ),
                )
              : AppFileImage(
                  path: iconUrl,
                  width: 58,
                  height: 58,
                  fallback: AppIcon(
                    AppIcons.server,
                    color: AppTokens.textMuted,
                  ),
                ),
        ),
        AppButton(
          label: loading ? 'Enviando' : 'Alterar ícone',
          icon: AppIcons.image,
          size: AppButtonSize.sm,
          variant: AppButtonVariant.secondary,
          loading: loading,
          onPressed: enabled && !loading ? onPick : null,
        ),
        if (iconUrl != null)
          AppButton(
            label: 'Remover',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.ghost,
            onPressed: enabled && !loading ? onRemove : null,
          ),
      ],
    );
  }
}

String? _contentTypeFor(String fileName) {
  return switch (fileName.split('.').last.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };
}
