import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/profile_repository.dart';
import '../../features/servers/servers_providers.dart';
import '../../shared/models/profile.dart';
import '../../shared/models/servers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../theme/appearance_theme.dart';
import 'ds_tokens.dart';
import 'inputs/app_color_picker.dart';
import 'inputs/app_select.dart';
import 'profile_card.dart';
import 'profile_crop.dart';

/// Editor com um único draft por escopo e preview persistente.
class ProfileEditorDialog extends ConsumerStatefulWidget {
  const ProfileEditorDialog({super.key});

  @override
  ConsumerState<ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<ProfileEditorDialog> {
  static const _images = XTypeGroup(
    label: 'Imagens',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
  );
  static const _swatches = [
    '#5B76FF',
    '#62D6B0',
    '#E39A62',
    '#C484E7',
    '#27365B',
    '#181C28',
  ];

  String? _serverId;
  ProfileEditorData? _data;
  List<CosmeticItem> _catalog = const [];
  List<ProfileFont> _fonts = const [];
  bool _loading = true;
  bool _saving = false;
  bool _preparing = false;
  bool _allowClose = false;
  bool _compactPreview = false;
  bool _avatarCropExpanded = false;
  bool _bannerCropExpanded = false;
  int _effectReplay = 0;
  String? _error;
  String? _usernameHint;
  bool? _usernameAvailable;
  Timer? _usernameTimer;
  final Map<String, dynamic> _mainChanges = {};
  final Map<String, dynamic> _serverChanges = {};
  final Set<String> _inherit = {};
  Uint8List? _avatarBytes;
  Uint8List? _bannerBytes;
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _nickname = TextEditingController();
  final _bio = TextEditingController();

  bool get _dirty =>
      _mainChanges.isNotEmpty ||
      _serverChanges.isNotEmpty ||
      _inherit.isNotEmpty;
  bool get _isServer => _serverId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _nickname.dispose();
    _bio.dispose();
    _usernameTimer?.cancel();
    super.dispose();
  }

  Future<void> _load([String? scope]) async {
    setState(() {
      _loading = true;
      _error = null;
      _serverId = scope;
    });
    try {
      final repository = ref.read(profileRepositoryProvider);
      final editor = await repository.editor(scope);
      final catalog = _catalog.isEmpty ? await repository.catalog() : _catalog;
      final fonts = _fonts.isEmpty ? await repository.fonts() : _fonts;
      if (!mounted || _serverId != scope) return;
      _displayName.text = editor.mainResolved.displayName;
      _username.text = editor.mainResolved.username;
      _usernameHint = null;
      _usernameAvailable = null;
      _nickname.text = editor.resolved.nickname ?? '';
      _bio.text = editor.resolved.bio;
      setState(() {
        _data = editor;
        _catalog = catalog;
        _fonts = fonts;
        _mainChanges.clear();
        _serverChanges.clear();
        _inherit.clear();
        _avatarBytes = null;
        _bannerBytes = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Descartar alterações?'),
            content: const Text(
              'As alterações deste perfil ainda não foram salvas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Continuar editando'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Descartar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _close() async {
    if (await _confirmDiscard() && mounted) {
      setState(() => _allowClose = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _scope(String? id) async {
    if (id == _serverId || !await _confirmDiscard()) return;
    await _load(id);
  }

  void _set(String field, dynamic value, {String? inheritKey}) {
    setState(() {
      (_isServer && field != 'nickname'
              ? _serverChanges
              : _mainChanges)[field] =
          value;
      if (_isServer) _inherit.remove(inheritKey ?? field);
      _error = null;
    });
  }

  void _checkUsername(String value) {
    _usernameTimer?.cancel();
    if (value == _data?.mainResolved.username) {
      setState(() {
        _usernameAvailable = true;
        _usernameHint = 'Username atual';
      });
      return;
    }
    setState(() {
      _usernameAvailable = null;
      _usernameHint = 'Verificando disponibilidade…';
    });
    _usernameTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await ref
            .read(profileRepositoryProvider)
            .usernameAvailability(value);
        if (!mounted || _username.text != value) return;
        setState(() {
          _usernameAvailable = result.available;
          _usernameHint = result.available
              ? 'Disponível'
              : result.reason ?? 'Indisponível';
        });
      } catch (_) {
        if (mounted) {
          setState(
            () => _usernameHint = 'Disponibilidade será confirmada ao salvar',
          );
        }
      }
    });
  }

  void _resetField(String field) {
    if (!_isServer) return;
    setState(() {
      _inherit.add(field);
      _serverChanges.remove(field);
      if (field == 'avatarUrl') {
        _serverChanges.remove('avatarUploadId');
        _avatarBytes = null;
      }
      if (field == 'bannerUrl') {
        _serverChanges.remove('bannerUploadId');
        _bannerBytes = null;
      }
      if (field == 'style') _serverChanges.remove('style');
    });
  }

  dynamic _value(String field) {
    final data = _data;
    if (data == null) return null;
    final local = _isServer ? _serverChanges : _mainChanges;
    if (local.containsKey(field)) return local[field];
    if (_isServer && _inherit.contains(field)) {
      return data.mainResolved.toJson()[field];
    }
    return data.resolved.toJson()[field];
  }

  ProfileData _preview() {
    final data = _data!;
    final json = data.resolved.toJson();
    if (_isServer) {
      final global = data.mainResolved.toJson();
      for (final field in _inherit) {
        json[field] = global[field];
      }
      for (final entry in _serverChanges.entries) {
        final key = switch (entry.key) {
          'avatarUploadId' => 'avatarUrl',
          'bannerUploadId' => 'bannerUrl',
          _ => entry.key,
        };
        if (key == 'avatarUrl' || key == 'bannerUrl') {
          if (entry.value == null) json[key] = null;
        } else {
          json[key] = entry.value;
        }
      }
      if (_mainChanges.containsKey('nickname')) {
        json['name'] = _mainChanges['nickname'] ?? global['displayName'];
        json['nickname'] = _mainChanges['nickname'];
      }
    } else {
      for (final entry in _mainChanges.entries) {
        final key = switch (entry.key) {
          'avatarUploadId' => 'avatarUrl',
          'bannerUploadId' => 'bannerUrl',
          'displayName' => 'name',
          _ => entry.key,
        };
        if (key == 'avatarUrl' || key == 'bannerUrl') {
          if (entry.value == null) json[key] = null;
        } else {
          json[key] = entry.value;
        }
        if (entry.key == 'displayName') json['displayName'] = entry.value;
        if (entry.key == 'theme') json['theme'] = entry.value;
      }
    }
    return ProfileData.fromJson(json);
  }

  Future<void> _selectImage(bool banner) async {
    if (_preparing) return;
    final file = await openFile(acceptedTypeGroups: const [_images]);
    if (file == null) return;
    final ext = file.name.split('.').last.toLowerCase();
    final type = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => null,
    };
    if (type == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final limit = banner ? 10 * 1024 * 1024 : 5 * 1024 * 1024;
    if (bytes.length > limit) {
      setState(() => _error = 'Arquivo maior que ${banner ? 10 : 5} MB.');
      return;
    }
    final scope = _serverId;
    final previousBytes = banner ? _bannerBytes : _avatarBytes;
    setState(() {
      _preparing = true;
      if (banner) {
        _bannerBytes = bytes;
      } else {
        _avatarBytes = bytes;
      }
    });
    try {
      final id = await ref
          .read(profileRepositoryProvider)
          .prepareImage(
            bytes: bytes,
            fileName: file.name,
            contentType: type,
            banner: banner,
            serverId: scope,
          );
      if (!mounted || _serverId != scope) return;
      _set(
        banner ? 'bannerUploadId' : 'avatarUploadId',
        id,
        inheritKey: banner ? 'bannerUrl' : 'avatarUrl',
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          if (banner) {
            _bannerBytes = previousBytes;
          } else {
            _avatarBytes = previousBytes;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _preparing) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(profileRepositoryProvider);
      final editor = _isServer
          ? await repository.saveServer(_serverId!, {
              if (_mainChanges.containsKey('nickname'))
                'nickname': _mainChanges['nickname'],
              if (_inherit.isNotEmpty) 'inherit': _inherit.toList(),
              if (_serverChanges.isNotEmpty) 'overrides': _serverChanges,
            })
          : await repository.saveMain(_mainChanges);
      if (!mounted) return;
      setState(() {
        _data = editor;
        _mainChanges.clear();
        _serverChanges.clear();
        _inherit.clear();
        _avatarBytes = null;
        _bannerBytes = null;
      });
      try {
        await ref.read(authControllerProvider.notifier).refreshCurrentUser();
      } catch (_) {
        // O perfil já foi salvo; a sessão será atualizada na próxima leitura.
      }
      if (!mounted) return;
      try {
        final catalog = await repository.catalog();
        if (mounted) setState(() => _catalog = catalog);
      } catch (_) {
        // A atualização da biblioteca pode ser refeita ao reabrir o editor.
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetServer() async {
    if (_serverId == null) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Resetar perfil do servidor?'),
            content: const Text(
              'As personalizações deste servidor voltarão a herdar o Main Profile.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Resetar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      final result = await ref
          .read(profileRepositoryProvider)
          .resetServer(_serverId!);
      if (!mounted) return;
      await _load(_serverId);
      if (result.nicknamePreserved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nickname preservado: somente um administrador pode removê-lo.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _openCatalog() async {
    final item = await showDialog<CosmeticItem>(
      context: context,
      builder: (_) =>
          _CosmeticLibraryDialog(items: _catalog, serverScope: _isServer),
    );
    if (item == null || !mounted) return;
    final field = switch (item.category) {
      'AVATAR_DECORATION' => 'avatarDecorationId',
      'NAMEPLATE' => 'nameplateId',
      'PROFILE_EFFECT' => 'profileEffectId',
      'PROFILE_FRAME' => 'profileFrameId',
      _ => null,
    };
    if (field != null) _set(field, item.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final servers = ref.watch(serversProvider).valueOrNull ?? const [];
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_dirty || _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: colors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: colors.borderSubtle),
        ),
        child: SizedBox(
          width: 960,
          height: math.min(720, size.height - 32),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 720;
                  return Container(
                    padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 12, 12, 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.borderHairline),
                      ),
                    ),
                    child: narrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _dialogTitle()),
                                  _closeButton(),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _scopePicker(servers),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: _dialogTitle()),
                              SizedBox(
                                width: 248,
                                child: _scopePicker(servers),
                              ),
                              const SizedBox(width: 8),
                              _closeButton(),
                            ],
                          ),
                  );
                },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTokens.accentPurple),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _data == null
                    ? Center(
                        child: TextButton(
                          onPressed: () => _load(_serverId),
                          child: const Text('Tentar novamente'),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 720) {
                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                20,
                                16,
                                24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _previewPanel(),
                                  const SizedBox(height: 24),
                                  _form(),
                                ],
                              ),
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    8,
                                    24,
                                    32,
                                  ),
                                  child: _form(),
                                ),
                              ),
                              SizedBox(
                                width: 360,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: colors.surface1,
                                    border: Border(
                                      left: BorderSide(
                                        color: colors.borderHairline,
                                      ),
                                    ),
                                  ),
                                  child: SingleChildScrollView(
                                    child: _previewPanel(),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderHairline)),
                ),
                child: Row(
                  children: [
                    if (_isServer)
                      TextButton(
                        onPressed: _saving ? null : _resetServer,
                        child: const Text('Restaurar perfil'),
                      ),
                    const Spacer(),
                    if (_dirty)
                      Flexible(
                        child: Text(
                          'Alterações não salvas',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving || _preparing
                          ? null
                          : _dirty
                          ? () => _load(_serverId)
                          : _close,
                      child: Text(_dirty ? 'Descartar' : 'Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _dirty && !_saving && !_preparing
                          ? _save
                          : null,
                      child: Text(
                        _saving
                            ? 'Salvando…'
                            : _preparing
                            ? 'Preparando mídia…'
                            : 'Salvar',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogTitle() => Text(
    'Editar perfil',
    style: TextStyle(
      fontFamily: 'Geist',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: context.appColors.textPrimary,
    ),
  );

  Widget _closeButton() => IconButton(
    onPressed: _close,
    icon: const Icon(Icons.close, size: 20),
    tooltip: 'Fechar',
  );

  Widget _scopePicker(List<Server> servers) => AppSelect<String>(
    label: 'Perfil',
    value: _serverId ?? '',
    options: [
      const AppSelectOption(value: '', label: 'Perfil principal'),
      for (final server in servers)
        AppSelectOption(value: server.id, label: server.name),
    ],
    onChanged: _saving || _preparing
        ? null
        : (value) => _scope(value == '' ? null : value),
  );

  Widget _fieldLabel(String label) => Text(
    label,
    style: TextStyle(
      color: context.appColors.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _identityField({
    required String label,
    required TextEditingController controller,
    required int maxLength,
    required ValueChanged<String> onChanged,
    String? helper,
    String? status,
    Color? statusColor,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLength: maxLength,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: label,
            counterText: '',
            isDense: true,
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status != null || helper != null)
              Expanded(
                child: Text(
                  status ?? helper!,
                  style: TextStyle(
                    color: statusColor ?? context.appColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 8),
            Text(
              '${controller.text.characters.length}/$maxLength',
              style: TextStyle(
                color: context.appColors.textMuted,
                fontFamily: 'Geist Mono',
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _previewPanel() {
    final colors = context.appColors;
    final preview = _preview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isServer ? 'Prévia neste servidor' : 'Prévia do perfil',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Veja como seu perfil aparece para outras pessoas.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ProfileCard(
          profile: preview,
          catalog: _catalog,
          fonts: _fonts,
          avatarBytes: _avatarBytes,
          bannerBytes: _bannerBytes,
          compact: _compactPreview,
          replayToken: _effectReplay,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Completo')),
                ButtonSegment(value: true, label: Text('Compacto')),
              ],
              selected: {_compactPreview},
              onSelectionChanged: (value) =>
                  setState(() => _compactPreview = value.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            IconButton(
              onPressed: preview.profileEffectId == null
                  ? null
                  : () => setState(() => _effectReplay++),
              icon: const Icon(Icons.replay_outlined, size: 19),
              tooltip: 'Reproduzir efeito',
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }

  Widget _form() {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final manualStatus = auth is Authenticated
        ? auth.user.manualStatus
        : 'ONLINE';
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Identidade'),
        if (!_isServer) ...[
          _identityField(
            label: 'Nome de usuário',
            controller: _username,
            maxLength: 20,
            helper: 'Identificador único: 3–20 letras, números ou _',
            status: _usernameHint,
            statusColor: _usernameAvailable == false
                ? AppTokens.accentPurple
                : null,
            onChanged: (value) {
              _set('username', value.trim());
              _checkUsername(value.trim());
            },
          ),
          _identityField(
            label: 'Nome de exibição',
            controller: _displayName,
            maxLength: 50,
            onChanged: (value) => _set('displayName', value),
          ),
        ] else ...[
          _identityField(
            label: 'Apelido no servidor',
            controller: _nickname,
            maxLength: 50,
            enabled: _data?.server?['allowSelfNickname'] == true,
            helper: 'Em branco usa o nome de exibição',
            onChanged: (value) =>
                _set('nickname', value.trim().isEmpty ? null : value.trim()),
          ),
        ],
        _heading('Avatar e banner'),
        _mediaControls(false),
        _mediaControls(true),
        _heading('Nome e cores'),
        if (!_isServer) _cosmetic('Placa de nome', 'NAMEPLATE', 'nameplateId'),
        _property(
          'Estilo do nome',
          'style',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSelect<String>(
                label: 'Fonte',
                value: _currentFontId(),
                options: [
                  for (final font in _fonts)
                    AppSelectOption(value: font.id, label: font.name),
                ],
                onChanged: _fonts.isEmpty
                    ? null
                    : (value) => _changeStyle(font: value),
              ),
              const SizedBox(height: 14),
              AppSelect<String>(
                label: 'Efeito',
                value:
                    (_value('style') as Map?)?['effectId'] as String? ??
                    'solid',
                options:
                    const [
                          'solid',
                          'gradient',
                          'neon',
                          'toon',
                          'pop',
                          'gummy',
                          'prism',
                        ]
                        .map(
                          (value) => AppSelectOption(
                            value: value,
                            label: switch (value) {
                              'solid' => 'Sólido',
                              'gradient' => 'Gradiente',
                              'neon' => 'Neon',
                              'toon' => 'Cartoon',
                              'pop' => 'Pop',
                              'gummy' => 'Goma',
                              _ => 'Prisma',
                            },
                          ),
                        )
                        .toList(),
                onChanged: (value) => _changeStyle(effect: value),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _styleColorCount(); index++)
                _colorChoices(
                  'Cor ${index + 1}',
                  _styleColor(index),
                  (value) => _changeStyle(color: value, colorIndex: index),
                ),
              TextButton(
                onPressed: () => _set('style', null),
                child: const Text('Restaurar estilo padrão'),
              ),
            ],
          ),
        ),
        _property(
          'Cores do perfil',
          'theme',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _colorChoices(
                'Cor primária',
                (_value('theme') as Map?)?['primary'] as String?,
                (value) => _changeTheme(primary: value),
              ),
              _colorChoices(
                'Cor de destaque',
                (_value('theme') as Map?)?['accent'] as String?,
                (value) => _changeTheme(accent: value),
              ),
              TextButton(
                onPressed: () => _set('theme', null),
                child: const Text('Restaurar tema padrão'),
              ),
            ],
          ),
        ),
        _heading('Decorações'),
        OutlinedButton.icon(
          onPressed: _openCatalog,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Catálogo e biblioteca'),
        ),
        _cosmetic(
          'Decoração do avatar',
          'AVATAR_DECORATION',
          'avatarDecorationId',
        ),
        _cosmetic('Efeito do perfil', 'PROFILE_EFFECT', 'profileEffectId'),
        _cosmetic('Moldura do perfil', 'PROFILE_FRAME', 'profileFrameId'),
        _heading('Sobre você'),
        _property(
          'Biografia',
          'bio',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _insertMarkdown('**', '**'),
                    child: const Text('Negrito'),
                  ),
                  TextButton(
                    onPressed: () => _insertMarkdown('*', '*'),
                    child: const Text('Itálico'),
                  ),
                  TextButton(
                    onPressed: () => _insertMarkdown('__', '__'),
                    child: const Text('Sublinhado'),
                  ),
                  TextButton(
                    onPressed: () => _insertMarkdown('[', '](https://)'),
                    child: const Text('Link'),
                  ),
                ],
              ),
              TextField(
                controller: _bio,
                maxLines: 5,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Escreva sobre você',
                ),
                onChanged: (value) => _set('bio', value),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_visibleBioCount(_bio.text)}/${_isServer ? 190 : 300} caracteres visíveis',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontFamily: 'Geist Mono',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!_isServer) ...[
          _heading('Presença'),
          AppSelect<String>(
            label: 'Status',
            value: manualStatus,
            options: const [
              AppSelectOption(value: 'ONLINE', label: 'Online'),
              AppSelectOption(value: 'IDLE', label: 'Ausente'),
              AppSelectOption(value: 'DND', label: 'Não perturbe'),
              AppSelectOption(value: 'INVISIBLE', label: 'Invisível'),
            ],
            onChanged: (status) async {
              try {
                await ref.read(profileRepositoryProvider).setStatus(status);
                await ref
                    .read(authControllerProvider.notifier)
                    .refreshCurrentUser();
              } catch (error) {
                if (mounted) setState(() => _error = '$error');
              }
            },
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Os itens do catálogo são gratuitos. Ao equipar, ficam permanentemente na sua biblioteca.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _mediaControls(bool banner) {
    final expanded = banner ? _bannerCropExpanded : _avatarCropExpanded;
    final field = banner ? 'bannerUrl' : 'avatarUrl';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _property(
          banner ? 'Banner' : 'Avatar',
          field,
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _preparing ? null : () => _selectImage(banner),
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(banner ? 'Escolher banner' : 'Escolher avatar'),
              ),
              TextButton(
                onPressed: _preparing
                    ? null
                    : () {
                        if (banner) {
                          _bannerBytes = null;
                        } else {
                          _avatarBytes = null;
                        }
                        _set(
                          banner ? 'bannerUploadId' : 'avatarUploadId',
                          null,
                          inheritKey: field,
                        );
                      },
                child: const Text('Remover'),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  if (banner) {
                    _bannerCropExpanded = !expanded;
                  } else {
                    _avatarCropExpanded = !expanded;
                  }
                }),
                icon: Icon(expanded ? Icons.expand_less : Icons.tune, size: 18),
                label: Text(expanded ? 'Ocultar ajuste' : 'Ajustar recorte'),
              ),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: _cropControls(
              banner ? 'bannerCrop' : 'avatarCrop',
              banner ? 'Recorte do banner' : 'Recorte do avatar',
            ),
          ),
      ],
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != 'Identidade') ...[
          Divider(height: 1, color: context.appColors.borderHairline),
          const SizedBox(height: 14),
        ],
        Text(
          title,
          style: TextStyle(
            color: context.appColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _property(String label, String key, Widget child) {
    final changed =
        _serverChanges.containsKey(key) ||
        (key == 'avatarUrl' && _serverChanges.containsKey('avatarUploadId')) ||
        (key == 'bannerUrl' && _serverChanges.containsKey('bannerUploadId'));
    final inherited =
        _isServer &&
        (_inherit.contains(key) ||
            (!changed &&
                !((_data?.server?['overrides'] as Map?)?.containsKey(key) ??
                    false)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isServer)
                TextButton(
                  onPressed: inherited ? null : () => _resetField(key),
                  child: Text(
                    inherited
                        ? 'Herdado do perfil principal'
                        : 'Voltar a herdar',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }

  Widget _cosmetic(String label, String category, String key) {
    final items = _catalog.where((item) => item.category == category).toList();
    final colors = context.appColors;
    Widget choice(
      String title,
      bool selected,
      VoidCallback onSelected, {
      Color? swatch,
    }) => ChoiceChip(
      label: Text(title),
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: swatch == null
          ? null
          : CircleAvatar(backgroundColor: swatch, radius: 9),
      labelStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
      selectedColor: colors.surface3,
      backgroundColor: colors.surface2,
      checkmarkColor: colors.textPrimary,
      side: BorderSide(color: selected ? colors.accent : colors.borderSubtle),
    );
    return _property(
      label,
      key,
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          choice('Nenhum', _value(key) == null, () => _set(key, null)),
          for (final item in items)
            choice(
              '${item.name}${item.owned ? ' · possuído' : ''}${item.equippedServers.isNotEmpty ? ' · outro perfil' : ''}',
              _value(key) == item.id,
              () => _set(key, item.id),
              swatch:
                  profileHexColor(item.visual['color'] as String?) ??
                  colors.accent,
            ),
        ],
      ),
    );
  }

  Widget _cropControls(String field, String title) {
    final crop = ProfileCrop.fromJson(
      (_value(field) as Map?)?.cast<String, dynamic>(),
    );

    return _property(
      title,
      field,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zoom',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Slider(
            value: crop.zoom,
            min: 1,
            max: 3,
            onChanged: (value) => _set(field, crop.withZoom(value).toJson()),
          ),
          Text(
            'Horizontal',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Slider(
            value: crop.horizontal,
            onChanged: (value) =>
                _set(field, crop.withHorizontal(value).toJson()),
          ),
          Text(
            'Vertical',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Slider(
            value: crop.vertical,
            onChanged: (value) =>
                _set(field, crop.withVertical(value).toJson()),
          ),
          if (crop.zoom == 1)
            Text(
              'Mover o recorte aplica zoom de 1,5× para permitir o deslocamento.',
              style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _colorChoices(
    String label,
    String? current,
    ValueChanged<String> onSelect,
  ) => AppColorPicker(
    label: label,
    value: current,
    swatches: _swatches,
    onChanged: onSelect,
  );

  void _changeTheme({String? primary, String? accent}) {
    final current = (_value('theme') as Map?)?.cast<String, dynamic>();
    _set('theme', {
      'primary': primary ?? current?['primary'] ?? _swatches[4],
      'accent': accent ?? current?['accent'] ?? _swatches[0],
    });
  }

  int _styleColorCount() => switch ((_value('style') as Map?)?['effectId']) {
    'gradient' => 2,
    'prism' => 3,
    _ => 1,
  };

  String _currentFontId() {
    final id = (_value('style') as Map?)?['fontId'] as String? ?? 'geist';
    return _fonts.any((font) => font.id == id)
        ? id
        : (_fonts.isNotEmpty ? _fonts.first.id : 'geist');
  }

  String? _styleColor(int index) {
    final colors = (_value('style') as Map?)?['colors'] as List?;
    return colors != null && colors.length > index
        ? colors[index] as String?
        : null;
  }

  void _changeStyle({
    String? font,
    String? effect,
    String? color,
    int colorIndex = 0,
  }) {
    final current = (_value('style') as Map?)?.cast<String, dynamic>();
    final nextEffect = effect ?? current?['effectId'] ?? 'solid';
    final count = switch (nextEffect) {
      'gradient' => 2,
      'prism' => 3,
      _ => 1,
    };
    final colors = List<String>.generate(
      count,
      (index) => _styleColor(index) ?? _swatches[index],
    );
    if (color != null) colors[colorIndex] = color;
    _set('style', {
      'fontId': font ?? _currentFontId(),
      'effectId': nextEffect,
      'colors': colors,
    });
  }

  void _insertMarkdown(String before, String after) {
    final selection = _bio.selection;
    final text = _bio.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final selected = text.substring(start, end);
    final updated = text.replaceRange(start, end, '$before$selected$after');
    _bio.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: start + before.length + selected.length,
      ),
    );
    _set('bio', updated);
  }

  int _visibleBioCount(String value) => value
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\(https?://[^)]*\)'),
        (match) => match[1] ?? '',
      )
      .replaceAll(RegExp(r'\*\*|__|\*|_'), '')
      .characters
      .length;
}

class _CosmeticLibraryDialog extends StatelessWidget {
  const _CosmeticLibraryDialog({
    required this.items,
    required this.serverScope,
  });
  final List<CosmeticItem> items;
  final bool serverScope;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    Widget list(bool library) {
      final visible = items
          .where(
            (item) =>
                (!library || item.owned) &&
                (!serverScope || item.category != 'NAMEPLATE'),
          )
          .toList();
      return visible.isEmpty
          ? const Center(child: Text('Nenhum item nesta seção'))
          : ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final item = visible[index];
                final color =
                    profileHexColor(item.visual['color'] as String?) ??
                    colors.accent;
                return ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .25),
                      border: Border.all(color: color, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.category.replaceAll('_', ' ').toLowerCase()} · ${item.owned ? 'Possuído' : 'Grátis'}${item.equippedMain ? ' · Equipado no Main Profile' : ''}${item.equippedServers.isNotEmpty ? ' · Equipado em servidor' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, item),
                );
              },
            );
    }

    return DefaultTabController(
      length: 2,
      child: Dialog(
        backgroundColor: colors.surface1,
        child: SizedBox(
          width: 620,
          height: 570,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cosméticos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Catálogo'),
                  Tab(text: 'Minha biblioteca'),
                ],
              ),
              Expanded(child: TabBarView(children: [list(false), list(true)])),
            ],
          ),
        ),
      ),
    );
  }
}
