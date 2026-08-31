import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/user.dart';
import '../../api/api_exception.dart';
import '../../auth/auth_controller.dart';
import '../../auth/auth_state.dart';
import '../../storage/api_storage_service.dart';
import '../ui.dart';

/// Conta do usuário dentro do modal principal de configurações.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key, this.onCloseSettings});

  /// Fecha o modal pai após uma troca de senha, que encerra a sessão atual.
  final VoidCallback? onCloseSettings;

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  bool _emailVisible = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final user = authState is Authenticated ? authState.user : null;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('CONTA'),
        _ProfileSummary(
          user: user,
          onEdit: () => _openProfileDialog(context, user),
        ),
        const SizedBox(height: 16),
        _AccountRow(
          label: 'E-MAIL',
          value: _emailVisible ? user.email ?? '—' : _maskEmail(user.email),
          actions: [
            AppButton(
              label: _emailVisible ? 'Ocultar' : 'Revelar',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: () => setState(() => _emailVisible = !_emailVisible),
            ),
            AppIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Editar e-mail',
              onPressed: () => _openEmailDialog(context, user),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AccountRow(label: 'ID', value: user.id),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Divider(color: AppTokens.borderHairline, height: 1),
        ),
        const SectionHeader('SENHA E SEGURANÇA'),
        _AccountRow(
          label: 'SENHA',
          value: '••••••••',
          actions: [
            AppButton(
              label: 'Alterar',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.secondary,
              onPressed: () => _openPasswordDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openProfileDialog(BuildContext context, User user) {
    return showMacModalWindow<void>(
      context: context,
      title: 'Editar perfil',
      maxWidth: 460,
      child: _ProfileEditDialog(initialUser: user),
    );
  }

  Future<void> _openEmailDialog(BuildContext context, User user) {
    return showMacModalWindow<void>(
      context: context,
      title: 'Alterar e-mail',
      maxWidth: 420,
      child: _EmailEditDialog(initialEmail: user.email ?? ''),
    );
  }

  Future<void> _openPasswordDialog(BuildContext context) {
    return showMacModalWindow<void>(
      context: context,
      title: 'Alterar senha',
      maxWidth: 420,
      child: _PasswordEditDialog(
        onChanged: () => widget.onCloseSettings?.call(),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.user, required this.onEdit});

  final User user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface3,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTokens.borderSubtle, width: 1),
      ),
      child: Row(
        children: [
          _Avatar(user: user, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@${user.username}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: 'Editar',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.secondary,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.label,
    required this.value,
    this.actions = const [],
  });

  final String label;
  final String value;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Geist Mono',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTokens.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13.5,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.size});

  final User user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = user.name.isEmpty ? '?' : user.name[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppTokens.borderHairline, width: 1),
      ),
      child: user.avatarUrl == null
          ? _AvatarInitial(value: initial, size: size)
          : Image.network(
              user.avatarUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _AvatarInitial(value: initial, size: size),
            ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.value, required this.size});

  final String value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: TextStyle(
        fontFamily: 'Geist',
        fontSize: size * 0.36,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
      ),
    );
  }
}

class _ProfileEditDialog extends ConsumerStatefulWidget {
  const _ProfileEditDialog({required this.initialUser});

  final User initialUser;

  @override
  ConsumerState<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends ConsumerState<_ProfileEditDialog> {
  static final _usernameRegex = RegExp(r'^[a-z0-9_]{3,20}$');
  static const _imageTypeGroup = XTypeGroup(
    label: 'Imagens',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  bool _savingProfile = false;
  bool _savingAvatar = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialUser.name);
    _usernameController = TextEditingController(
      text: widget.initialUser.username,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  User get _user {
    final authState = ref.read(authControllerProvider).valueOrNull;
    return authState is Authenticated ? authState.user : widget.initialUser;
  }

  Future<void> _pickAvatar() async {
    if (_savingAvatar) return;
    final file = await openFile(acceptedTypeGroups: const [_imageTypeGroup]);
    if (file == null) {
      return;
    }
    final contentType = _contentTypeFor(file.name);
    if (contentType == null) {
      setState(() => _error = 'Formato de imagem não suportado.');
      return;
    }

    setState(() {
      _savingAvatar = true;
      _error = null;
    });
    try {
      await ref
          .read(storageServiceProvider)
          .uploadAvatar(
            bytes: await file.readAsBytes(),
            fileName: file.name,
            contentType: contentType,
          );
      await ref.read(authControllerProvider.notifier).refreshCurrentUser();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Falha ao enviar a imagem. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_user.avatarUrl == null || _savingAvatar) return;
    setState(() {
      _savingAvatar = true;
      _error = null;
    });
    try {
      await ref.read(storageServiceProvider).deleteAvatar();
      await ref.read(authControllerProvider.notifier).refreshCurrentUser();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível remover o avatar.');
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (_savingProfile || !_formKey.currentState!.validate()) return;
    setState(() {
      _savingProfile = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            name: _nameController.text.trim(),
            username: _usernameController.text.trim().toLowerCase(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil atualizado.')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _Avatar(user: user, size: 72)),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                AppButton(
                  label: _savingAvatar ? 'Enviando' : 'Alterar avatar',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.secondary,
                  loading: _savingAvatar,
                  onPressed: _savingAvatar ? null : _pickAvatar,
                ),
                if (user.avatarUrl != null)
                  AppButton(
                    label: 'Remover',
                    size: AppButtonSize.sm,
                    variant: AppButtonVariant.ghost,
                    onPressed: _savingAvatar ? null : _removeAvatar,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _nameController,
              label: 'Nome',
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                final name = value?.trim() ?? '';
                return name.isEmpty || name.length > 50
                    ? 'Informe um nome de 1 a 50 caracteres.'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _usernameController,
              label: 'Username',
              validator: (value) {
                final username = value?.trim().toLowerCase() ?? '';
                return _usernameRegex.hasMatch(username)
                    ? null
                    : 'Use 3–20 caracteres: a-z, 0-9 ou _.';
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorText(_error!),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  onPressed: _savingProfile
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Salvar',
                  loading: _savingProfile,
                  onPressed: _savingProfile ? null : _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailEditDialog extends ConsumerStatefulWidget {
  const _EmailEditDialog({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_EmailEditDialog> createState() => _EmailEditDialogState();
}

class _EmailEditDialogState extends ConsumerState<_EmailEditDialog> {
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changeEmail(
            currentPassword: _passwordController.text,
            newEmail: _emailController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('E-mail atualizado.')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Confirme sua senha para trocar o e-mail usado no login.',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: AppTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            AppTextField(
              controller: _emailController,
              label: 'Novo e-mail',
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              validator: (value) => _emailRegex.hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Informe um e-mail válido.',
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _passwordController,
              label: 'Senha atual',
              obscureText: true,
              validator: (value) =>
                  (value?.length ?? 0) >= 8 ? null : 'Informe sua senha atual.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorText(_error!),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Salvar',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordEditDialog extends ConsumerStatefulWidget {
  const _PasswordEditDialog({required this.onChanged});

  final VoidCallback onChanged;

  @override
  ConsumerState<_PasswordEditDialog> createState() =>
      _PasswordEditDialogState();
}

class _PasswordEditDialogState extends ConsumerState<_PasswordEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onChanged();
      messenger.showSnackBar(
        const SnackBar(content: Text('Senha alterada. Faça login novamente.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _currentController,
              label: 'Senha atual',
              autofocus: true,
              obscureText: true,
              validator: (value) =>
                  (value?.length ?? 0) >= 8 ? null : 'Informe sua senha atual.',
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _newController,
              label: 'Nova senha',
              obscureText: true,
              validator: (value) => (value?.length ?? 0) >= 8
                  ? null
                  : 'A senha deve ter ao menos 8 caracteres.',
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _confirmationController,
              label: 'Confirmar nova senha',
              obscureText: true,
              validator: (value) => value == _newController.text
                  ? null
                  : 'As senhas não coincidem.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorText(_error!),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Alterar senha',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        color: AppTokens.accentPurple,
      ),
    );
  }
}

String _maskEmail(String? email) {
  if (email == null || email.isEmpty) return '—';
  final atIndex = email.indexOf('@');
  if (atIndex <= 0) return '••••••••';
  return '${email.substring(0, 1)}••••@${email.substring(atIndex + 1)}';
}

String? _contentTypeFor(String fileName) {
  return switch (fileName.split('.').last.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => null,
  };
}
