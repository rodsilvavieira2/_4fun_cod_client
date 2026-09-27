import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/profile_repository.dart';
import '../../features/servers/servers_providers.dart';
import '../../shared/models/profile.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../theme/appearance_theme.dart';
import 'profile_card.dart';

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
    return PopScope(
      canPop: !_dirty || _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        backgroundColor: colors.surface1,
        child: SizedBox(
          width: 1060,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
                child: Row(
                  children: [
                    Text(
                      'Editar perfil',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 270,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('scope-${_serverId ?? 'main'}'),
                        initialValue: _serverId ?? '',
                        decoration: const InputDecoration(labelText: 'Escopo'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Main Profile'),
                          ),
                          for (final server in servers)
                            DropdownMenuItem(
                              value: server.id,
                              child: Text(
                                'Perfil em ${server.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _saving || _preparing
                            ? null
                            : (value) => _scope(value == '' ? null : value),
                      ),
                    ),
                    IconButton(
                      onPressed: _close,
                      icon: const Icon(Icons.close),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
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
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 8, 16, 24),
                              child: _form(),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                24,
                                24,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: colors.borderSubtle),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Prévia ${_isServer ? 'neste servidor' : 'global'}',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      ChoiceChip(
                                        label: const Text('Completo'),
                                        selected: !_compactPreview,
                                        onSelected: (_) => setState(
                                          () => _compactPreview = false,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      ChoiceChip(
                                        label: const Text('Compacto'),
                                        selected: _compactPreview,
                                        onSelected: (_) => setState(
                                          () => _compactPreview = true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ProfileCard(
                                    profile: _preview(),
                                    catalog: _catalog,
                                    fonts: _fonts,
                                    avatarBytes: _avatarBytes,
                                    bannerBytes: _bannerBytes,
                                    compact: _compactPreview,
                                    replayToken: _effectReplay,
                                  ),
                                  TextButton(
                                    onPressed:
                                        _preview().profileEffectId == null
                                        ? null
                                        : () => setState(() => _effectReplay++),
                                    child: const Text('Reproduzir efeito'),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'As alterações aparecem aqui antes de salvar.',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                child: Row(
                  children: [
                    if (_isServer)
                      TextButton(
                        onPressed: _saving ? null : _resetServer,
                        child: const Text('Reset Server Profile'),
                      ),
                    const Spacer(),
                    if (_dirty)
                      Text(
                        'Alterações não salvas',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _dirty ? () => _load(_serverId) : _close,
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
          TextField(
            controller: _username,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'Username',
              helperText: 'Identificador único: 3–20 letras, números ou _',
            ),
            onChanged: (value) {
              _set('username', value.trim());
              _checkUsername(value.trim());
            },
          ),
          if (_usernameHint != null)
            Text(
              _usernameHint!,
              style: TextStyle(
                color: _usernameAvailable == false
                    ? Colors.redAccent
                    : context.appColors.textSecondary,
                fontSize: 12,
              ),
            ),
          TextField(
            controller: _displayName,
            maxLength: 50,
            decoration: const InputDecoration(labelText: 'Display Name'),
            onChanged: (value) => _set('displayName', value),
          ),
        ] else ...[
          TextField(
            controller: _nickname,
            maxLength: 50,
            enabled: _data?.server?['allowSelfNickname'] == true,
            decoration: const InputDecoration(
              labelText: 'Server Nickname',
              helperText: 'Em branco usa o Display Name',
            ),
            onChanged: (value) =>
                _set('nickname', value.trim().isEmpty ? null : value.trim()),
          ),
        ],
        _heading('Avatar e banner'),
        _property(
          'Avatar',
          'avatarUrl',
          Row(
            children: [
              OutlinedButton(
                onPressed: _preparing ? null : () => _selectImage(false),
                child: const Text('Escolher avatar'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _avatarBytes = null;
                  _set('avatarUploadId', null, inheritKey: 'avatarUrl');
                },
                child: const Text('Remover'),
              ),
            ],
          ),
        ),
        _cropControls('avatarCrop', 'Crop do avatar'),
        _property(
          'Banner',
          'bannerUrl',
          Row(
            children: [
              OutlinedButton(
                onPressed: _preparing ? null : () => _selectImage(true),
                child: const Text('Escolher banner'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _bannerBytes = null;
                  _set('bannerUploadId', null, inheritKey: 'bannerUrl');
                },
                child: const Text('Remover'),
              ),
            ],
          ),
        ),
        _cropControls('bannerCrop', 'Crop do banner'),
        _heading('Nome e cores'),
        if (!_isServer) _cosmetic('Nameplate', 'NAMEPLATE', 'nameplateId'),
        _property(
          'Display Name Style',
          'style',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('font-${_serverId ?? 'main'}-${_value('style')}'),
                initialValue: _currentFontId(),
                decoration: const InputDecoration(labelText: 'Fonte'),
                items: [
                  for (final font in _fonts)
                    DropdownMenuItem(value: font.id, child: Text(font.name)),
                ],
                onChanged: (value) => _changeStyle(font: value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'effect-${_serverId ?? 'main'}-${_value('style')}',
                ),
                initialValue:
                    (_value('style') as Map?)?['effectId'] as String? ??
                    'solid',
                decoration: const InputDecoration(labelText: 'Efeito'),
                items:
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
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
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
          'Profile Theme',
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
                'Accent',
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
        _heading('Cosméticos'),
        OutlinedButton.icon(
          onPressed: _openCatalog,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Catálogo e biblioteca'),
        ),
        _cosmetic(
          'Avatar Decoration',
          'AVATAR_DECORATION',
          'avatarDecorationId',
        ),
        _cosmetic('Profile Effect', 'PROFILE_EFFECT', 'profileEffectId'),
        _cosmetic('Profile Frame', 'PROFILE_FRAME', 'profileFrameId'),
        _heading('Bio'),
        _property(
          'About Me',
          'bio',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                decoration: InputDecoration(
                  labelText: 'Bio',
                  helperText:
                      '${_visibleBioCount(_bio.text)}/${_isServer ? 190 : 300} caracteres visíveis',
                ),
                onChanged: (value) => _set('bio', value),
              ),
            ],
          ),
        ),
        if (!_isServer) ...[
          _heading('Presença'),
          DropdownButtonFormField<String>(
            key: ValueKey('manual-status-$manualStatus'),
            initialValue: manualStatus,
            decoration: const InputDecoration(labelText: 'Online Status'),
            items: const [
              DropdownMenuItem(value: 'ONLINE', child: Text('Online')),
              DropdownMenuItem(value: 'IDLE', child: Text('Ausente')),
              DropdownMenuItem(value: 'DND', child: Text('Não perturbe')),
              DropdownMenuItem(value: 'INVISIBLE', child: Text('Invisível')),
            ],
            onChanged: (status) async {
              if (status != null) {
                try {
                  await ref.read(profileRepositoryProvider).setStatus(status);
                  await ref
                      .read(authControllerProvider.notifier)
                      .refreshCurrentUser();
                } catch (error) {
                  if (mounted) setState(() => _error = '$error');
                }
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

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
    child: Text(
      title,
      style: TextStyle(
        color: context.appColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_isServer)
                TextButton(
                  onPressed: inherited ? null : () => _resetField(key),
                  child: Text(
                    inherited ? 'Herdado do Main Profile' : 'Voltar a herdar',
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
    return _property(
      label,
      key,
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Nenhum'),
            selected: _value(key) == null,
            onSelected: (_) => _set(key, null),
          ),
          for (final item in items)
            ChoiceChip(
              label: Text(
                '${item.name}${item.owned ? ' · possuído' : ''}${item.equippedServers.isNotEmpty ? ' · outro perfil' : ''}',
              ),
              selected: _value(key) == item.id,
              avatar: CircleAvatar(
                backgroundColor:
                    profileHexColor(item.visual['color'] as String?) ??
                    context.appColors.accent,
                radius: 9,
              ),
              onSelected: (_) => _set(key, item.id),
            ),
        ],
      ),
    );
  }

  Widget _cropControls(String field, String title) {
    final crop = (_value(field) as Map?)?.cast<String, dynamic>();
    final width = (crop?['width'] as num?)?.toDouble() ?? 1;
    final zoom = (1 / width).clamp(1.0, 3.0);
    final x = (crop?['x'] as num?)?.toDouble() ?? 0;
    final y = (crop?['y'] as num?)?.toDouble() ?? 0;
    final horizontal = width >= 1 ? .5 : (x / (1 - width)).clamp(0.0, 1.0);
    final vertical = width >= 1 ? .5 : (y / (1 - width)).clamp(0.0, 1.0);
    void update(double nextZoom, double nextX, double nextY) {
      final fraction = 1 / nextZoom;
      _set(field, {
        'x': (1 - fraction) * nextX,
        'y': (1 - fraction) * nextY,
        'width': fraction,
        'height': fraction,
      });
    }

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
            value: zoom,
            min: 1,
            max: 3,
            onChanged: (value) => update(value, horizontal, vertical),
          ),
          Text(
            'Horizontal',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Slider(
            value: horizontal,
            onChanged: (value) => update(zoom, value, vertical),
          ),
          Text(
            'Vertical',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Slider(
            value: vertical,
            onChanged: (value) => update(zoom, horizontal, value),
          ),
        ],
      ),
    );
  }

  Widget _colorChoices(
    String label,
    String? current,
    ValueChanged<String> onSelect,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: context.appColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 5),
      Wrap(
        spacing: 8,
        children: [
          for (final value in _swatches)
            InkWell(
              onTap: () => onSelect(value),
              child: Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: profileHexColor(value),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: current == value ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      SizedBox(
        width: 150,
        child: TextFormField(
          key: ValueKey('hex-$label-${_serverId ?? 'main'}-$current'),
          initialValue: current ?? '',
          decoration: const InputDecoration(hintText: '#RRGGBB', isDense: true),
          onFieldSubmitted: (value) {
            if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
              onSelect(value.toUpperCase());
            } else {
              setState(() => _error = 'Use uma cor no formato #RRGGBB.');
            }
          },
        ),
      ),
      const SizedBox(height: 9),
    ],
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
