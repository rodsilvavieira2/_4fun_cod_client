import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../native/native_media_backend.dart';

/// Modal Flutter próprio para seleção de compartilhamento de tela.
///
/// Estratégia por plataforma:
/// - Web: delega ao seletor nativo do navegador.
/// - Linux: não abre este modal e delega toda a escolha ao portal do sistema
///   por uma única sessão xdg-desktop-portal/PipeWire.
/// - Windows: lista janelas + displays via `desktopCapturer`, pois o backend
///   RTC dessa plataforma exige que o app forneça o sourceId.
///
/// O visual é inspirado no portal usado pelo OBS, mas a captura real continua
/// passando pelo backend seguro da plataforma.
class RtcScreenSharePicker {
  const RtcScreenSharePicker._();

  static Future<RtcScreenShareSelection?> show(
    BuildContext context, {
    required NativeScreenShareBackend backend,
    String titleText = 'Compartilhar tela',
    String screenTabText = 'Display',
    String windowTabText = 'Janela',
    String cancelText = 'Cancelar',
    String shareText = 'Compartilhar',
  }) {
    if (backend.capabilities.usesSystemPicker) {
      return Future.value(
        const RtcScreenShareSelection(
          kind: RtcScreenShareSourceKind.display,
          sourceId: null,
          usesSystemPicker: true,
        ),
      );
    }

    return showDialog<RtcScreenShareSelection>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ScreenShareDialog(
        backend: backend,
        titleText: titleText,
        screenTabText: screenTabText,
        windowTabText: windowTabText,
        cancelText: cancelText,
        shareText: shareText,
      ),
    );
  }
}

class _ScreenShareDialog extends StatefulWidget {
  const _ScreenShareDialog({
    required this.backend,
    required this.titleText,
    required this.screenTabText,
    required this.windowTabText,
    required this.cancelText,
    required this.shareText,
  });

  final NativeScreenShareBackend backend;
  final String titleText;
  final String screenTabText;
  final String windowTabText;
  final String cancelText;
  final String shareText;

  @override
  State<_ScreenShareDialog> createState() => _ScreenShareDialogState();
}

class _ScreenShareDialogState extends State<_ScreenShareDialog> {
  RtcScreenShareSourceKind _activeKind = RtcScreenShareSourceKind.window;
  List<RtcScreenShareSource> _sources = const [];
  String? _selectedId;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (!widget.backend.canUseKind(_activeKind)) {
      _activeKind = RtcScreenShareSourceKind.display;
    }
    unawaited(_loadSources());
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sources = await widget.backend.loadSources();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        if (_selectedId != null &&
            !_sources.any((source) => source.id == _selectedId)) {
          _selectedId = null;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar as fontes de compartilhamento.';
      });
    }
  }

  void _changeKind(RtcScreenShareSourceKind kind) {
    if (!widget.backend.canUseKind(kind)) {
      setState(() {
        _activeKind = kind;
        _selectedId = null;
      });
      return;
    }
    setState(() {
      _activeKind = kind;
      final selected = _selectedSource;
      if (selected == null || selected.kind != kind) {
        _selectedId = null;
      }
    });
  }

  RtcScreenShareSource? get _selectedSource {
    final selectedId = _selectedId;
    if (selectedId == null) return null;
    for (final source in _sources) {
      if (source.id == selectedId) return source;
    }
    return null;
  }

  List<RtcScreenShareSource> get _visibleSources {
    final sources = _sources
        .where((source) => source.kind == _activeKind)
        .toList(growable: false);
    sources.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return sources;
  }

  void _share() {
    final selected = _selectedSource;
    if (selected == null) return;
    Navigator.of(context).pop(
      RtcScreenShareSelection(
        kind: selected.kind,
        sourceId: selected.id,
        usesSystemPicker: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canUseActiveKind = widget.backend.canUseKind(_activeKind);
    final selected = _selectedSource;
    final disabledReason = widget.backend.disabledReasonFor(_activeKind);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      backgroundColor: const Color(0xFF1F2026),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF343640)),
      ),
      child: SizedBox(
        width: 660,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 16, 40, 20),
          child: Column(
            children: [
              _Header(
                title: widget.titleText,
                cancelText: widget.cancelText,
                shareText: widget.shareText,
                canShare: selected != null && canUseActiveKind,
                onCancel: () => Navigator.of(context).pop(),
                onShare: _share,
              ),
              const SizedBox(height: 36),
              Text(
                'Escolha o que você quer compartilhar na live.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFE7E7EA),
                ),
              ),
              const SizedBox(height: 20),
              _KindSwitch(
                activeKind: _activeKind,
                screenTabText: widget.screenTabText,
                windowTabText: widget.windowTabText,
                canUseWindow: widget.backend.canUseKind(
                  RtcScreenShareSourceKind.window,
                ),
                canUseDisplay: widget.backend.canUseKind(
                  RtcScreenShareSourceKind.display,
                ),
                onChanged: _changeKind,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _SourcePanel(
                  loading: _loading,
                  error: _error,
                  disabledReason: disabledReason,
                  sources: _visibleSources,
                  selectedId: _selectedId,
                  activeKind: _activeKind,
                  onRetry: _loadSources,
                  onSelect: (source) => setState(() {
                    _selectedId = source.id;
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.cancelText,
    required this.shareText,
    required this.canShare,
    required this.onCancel,
    required this.onShare,
  });

  final String title;
  final String cancelText;
  final String shareText;
  final bool canShare;
  final VoidCallback onCancel;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _DialogButton(
              label: cancelText,
              onPressed: onCancel,
              backgroundColor: const Color(0xFF383941),
              foregroundColor: Colors.white,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _DialogButton(
              label: shareText,
              onPressed: canShare ? onShare : null,
              backgroundColor: const Color(0xFF5F6B7A),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF56606D),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.disabledBackgroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? disabledBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(76, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: backgroundColor,
        disabledBackgroundColor: disabledBackgroundColor,
        foregroundColor: foregroundColor,
        disabledForegroundColor: const Color(0xFFB6BCC6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}

class _KindSwitch extends StatelessWidget {
  const _KindSwitch({
    required this.activeKind,
    required this.screenTabText,
    required this.windowTabText,
    required this.canUseWindow,
    required this.canUseDisplay,
    required this.onChanged,
  });

  final RtcScreenShareSourceKind activeKind;
  final String screenTabText;
  final String windowTabText;
  final bool canUseWindow;
  final bool canUseDisplay;
  final ValueChanged<RtcScreenShareSourceKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF34353D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TabButton(
              icon: Icons.web_asset_outlined,
              label: windowTabText,
              selected: activeKind == RtcScreenShareSourceKind.window,
              enabled: canUseWindow,
              onTap: () => onChanged(RtcScreenShareSourceKind.window),
            ),
            _TabButton(
              icon: Icons.desktop_windows_outlined,
              label: screenTabText,
              selected: activeKind == RtcScreenShareSourceKind.display,
              enabled: canUseDisplay,
              onTap: () => onChanged(RtcScreenShareSourceKind.display),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? Colors.white : const Color(0xFF9AA1AD);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF5B5C64) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({
    required this.loading,
    required this.error,
    required this.disabledReason,
    required this.sources,
    required this.selectedId,
    required this.activeKind,
    required this.onRetry,
    required this.onSelect,
  });

  final bool loading;
  final String? error;
  final String? disabledReason;
  final List<RtcScreenShareSource> sources;
  final String? selectedId;
  final RtcScreenShareSourceKind activeKind;
  final Future<void> Function() onRetry;
  final ValueChanged<RtcScreenShareSource> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3B44)),
      ),
      child: Padding(padding: const EdgeInsets.all(22), child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final disabled = disabledReason;
    if (disabled != null) {
      return Center(
        child: Text(
          disabled,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE7E7EA)),
        ),
      );
    }
    if (loading && sources.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B95A5)),
      );
    }
    final message = error;
    if (message != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: Color(0xFFE7E7EA))),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (sources.isEmpty) {
      return Center(
        child: Text(
          activeKind == RtcScreenShareSourceKind.window
              ? 'Nenhuma janela encontrada.'
              : 'Nenhum display encontrado.',
          style: const TextStyle(color: Color(0xFFE7E7EA)),
        ),
      );
    }
    if (activeKind == RtcScreenShareSourceKind.window) {
      return ListView.separated(
        itemCount: sources.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Color(0xFF24252B)),
        itemBuilder: (context, index) {
          final source = sources[index];
          return _WindowSourceTile(
            source: source,
            selected: selectedId == source.id,
            onTap: () => onSelect(source),
          );
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 460 ? 2 : 1;
        return GridView.builder(
          itemCount: sources.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: 16 / 9,
          ),
          itemBuilder: (context, index) {
            final source = sources[index];
            return _DisplaySourceCard(
              source: source,
              selected: selectedId == source.id,
              onTap: () => onSelect(source),
            );
          },
        );
      },
    );
  }
}

class _WindowSourceTile extends StatelessWidget {
  const _WindowSourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final RtcScreenShareSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF4B5362) : const Color(0xFF33343B),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _ThumbnailBox(
                width: 34,
                height: 34,
                thumbnail: source.thumbnail,
                icon: Icons.web_asset_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplaySourceCard extends StatelessWidget {
  const _DisplaySourceCard({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final RtcScreenShareSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: const Color(0xFF090A0D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF8FA8D8) : Colors.black,
              width: selected ? 2 : 3,
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _ThumbnailBox(
                  width: double.infinity,
                  height: double.infinity,
                  thumbnail: source.thumbnail,
                  icon: Icons.desktop_windows_outlined,
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      source.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbnailBox extends StatelessWidget {
  const _ThumbnailBox({
    required this.width,
    required this.height,
    required this.thumbnail,
    required this.icon,
  });

  final double width;
  final double height;
  final Uint8List? thumbnail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bytes = thumbnail;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF4A4B51),
          borderRadius: BorderRadius.circular(6),
        ),
        child: bytes == null
            ? Icon(icon, color: const Color(0xFFE1E3E8), size: 18)
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    Icon(icon, color: const Color(0xFFE1E3E8), size: 18),
              ),
      ),
    );
  }
}
