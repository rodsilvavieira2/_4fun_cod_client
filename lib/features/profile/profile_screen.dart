import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/storage/firebase_storage_service.dart';
import '../../shared/models/user.dart';

/// Perfil do usuário (Fase 1): dados editáveis, avatar via Firebase Storage
/// (upload direto do client — §3.9) e troca de senha com revoke-sessions.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static final _usernameRegex = RegExp(r'^[a-z0-9_]{3,20}$');
  static const _imageTypeGroup = XTypeGroup(
    label: 'Imagens',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
  );

  final _profileFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();

  final _passwordFormKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _savingProfile = false;
  bool _savingAvatar = false;
  bool _changingPassword = false;
  String? _profileError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final user = _currentUser();
    _nameController.text = user?.name ?? '';
    _usernameController.text = user?.username ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  User? _currentUser() {
    final authState = ref.read(authControllerProvider).valueOrNull;
    return authState is Authenticated ? authState.user : null;
  }

  Future<void> _saveProfile() async {
    if (_savingProfile || !_profileFormKey.currentState!.validate()) return;
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            name: _nameController.text.trim(),
            username: _usernameController.text.trim().toLowerCase(),
          );
      if (!mounted) return;
      setState(() {
        final user = _currentUser();
        _nameController.text = user?.name ?? _nameController.text;
        _usernameController.text = user?.username ?? _usernameController.text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _profileError = e.message);
    } catch (_) {
      if (mounted) setState(() => _profileError = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = _currentUser();
    if (user == null || _savingAvatar) return;

    final file = await openFile(acceptedTypeGroups: const [_imageTypeGroup]);
    if (file == null) return; // usuário cancelou
    final contentType = _contentTypeFor(file.path);
    if (contentType == null) {
      if (mounted) setState(() => _profileError = 'Formato de imagem não suportado.');
      return;
    }

    setState(() {
      _savingAvatar = true;
      _profileError = null;
    });
    try {
      // Upload direto para o Firebase Storage (avatars/{uid}/...) → URL.
      final storage = ref.read(storageServiceProvider);
      final url = await storage.uploadAvatar(
        uid: user.id,
        filePath: file.path,
        contentType: contentType,
      );
      // Backend só persiste a URL (`PATCH /users/me { avatarUrl }`).
      await ref.read(authControllerProvider.notifier).updateProfile(avatarUrl: url);
      // Best-effort: apaga o avatar ANTIGO no Storage (evita arquivos
      // órfãos acumulando custo a cada troca de avatar).
      final oldUrl = user.avatarUrl;
      final oldFileName = oldUrl == null ? null : _fileNameFromAvatarUrl(oldUrl);
      if (oldFileName != null) {
        try {
          await storage.deleteAvatar(uid: user.id, fileName: oldFileName);
        } catch (_) {
          // Arquivo órfão no Storage é aceitável; a URL nova já foi salva.
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _profileError = e.message);
    } catch (_) {
      if (mounted) setState(() => _profileError = 'Falha ao enviar a imagem. Tente novamente.');
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    final user = _currentUser();
    final url = user?.avatarUrl;
    if (user == null || url == null || _savingAvatar) return;

    setState(() {
      _savingAvatar = true;
      _profileError = null;
    });
    try {
      // Backend é a fonte de verdade: remove a URL primeiro.
      await ref.read(authControllerProvider.notifier).updateProfile(clearAvatar: true);
      // Best-effort: apaga o arquivo no Firebase Storage.
      final fileName = _fileNameFromAvatarUrl(url);
      if (fileName != null) {
        try {
          await ref.read(storageServiceProvider).deleteAvatar(uid: user.id, fileName: fileName);
        } catch (_) {
          // Arquivo órfão no Storage é aceitável; a URL já foi removida.
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _profileError = e.message);
    } catch (_) {
      if (mounted) setState(() => _profileError = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _changePassword() async {
    if (_changingPassword || !_passwordFormKey.currentState!.validate()) return;
    setState(() {
      _changingPassword = true;
      _passwordError = null;
    });
    // Captura o messenger ANTES do await: a tela é desmontada quando o
    // estado vira Unauthenticated (redirect para /login).
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      // Todas as sessões foram revogadas: o router redireciona para /login.
      messenger.showSnackBar(
        const SnackBar(content: Text('Senha alterada. Faça login novamente.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _passwordError = e.message);
    } catch (_) {
      if (mounted) setState(() => _passwordError = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
    // Redirect do router leva para /login automaticamente.
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final user = authState is Authenticated ? authState.user : null;
    if (user == null) {
      // Redirect do router (§7.2) já cuida de deslogados.
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAvatarSection(user),
                  const SizedBox(height: 24),
                  _buildProfileForm(user),
                  const SizedBox(height: 24),
                  _buildPasswordForm(),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _savingProfile || _savingAvatar || _changingPassword
                        ? null
                        : _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sair'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection(User user) {
    return Column(
      children: [
        CircleAvatar(
          radius: 48,
          foregroundImage: user.avatarUrl != null
              ? NetworkImage(user.avatarUrl!)
              : null,
          child: user.avatarUrl == null ? const Icon(Icons.person, size: 48) : null,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: _savingAvatar ? null : _pickAndUploadAvatar,
              icon: _savingAvatar
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              label: const Text('Alterar avatar'),
            ),
            if (user.avatarUrl != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _savingAvatar ? null : _removeAvatar,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remover avatar',
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildProfileForm(User user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _profileFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Dados do perfil', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                user.email,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Informe seu nome.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  // Normaliza igual ao submit (toLowerCase).
                  final username = value?.trim().toLowerCase() ?? '';
                  if (!_usernameRegex.hasMatch(username)) {
                    return 'Username inválido (a-z, 0-9, _; 3-20 caracteres).';
                  }
                  return null;
                },
              ),
              if (_profileError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _profileError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _savingProfile ? null : _saveProfile,
                  child: _savingProfile
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _passwordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Alterar senha', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _currentPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Senha atual',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Informe a senha atual.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Nova senha',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) =>
                    (value == null || value.length < 8) ? 'A senha deve ter pelo menos 8 caracteres.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nova senha',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) => value != _newPasswordController.text
                    ? 'As senhas não coincidem.'
                    : null,
              ),
              if (_passwordError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _passwordError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _changingPassword ? null : _changePassword,
                  child: _changingPassword
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Alterar senha'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Após alterar a senha, todas as sessões serão encerradas e você precisará entrar novamente.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mapeia a extensão do arquivo para o content-type aceito pelas
  /// Storage Security Rules (§3.9: image/jpeg|png|webp|gif).
  String? _contentTypeFor(String path) {
    return switch (path.split('.').last.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => null,
    };
  }

  /// Extrai o nome do arquivo da download URL do Firebase Storage
  /// (`.../o/avatars%2F<uid>%2F<file>?alt=media`).
  String? _fileNameFromAvatarUrl(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.isEmpty) return null;
      final decoded = Uri.decodeComponent(segments.last);
      return decoded.split('/').last;
    } catch (_) {
      return null;
    }
  }
}
