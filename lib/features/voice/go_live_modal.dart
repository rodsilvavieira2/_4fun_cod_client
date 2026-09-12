import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/screen_share_picker.dart';
import 'package:fourfun_cod_client/core/ui/settings_section_layout.dart';
import 'package:fourfun_cod_client/core/ui/ui.dart';

/// Qualidade de transmissão do modal Go Live — só opções possíveis, cada chip
/// mapeia 1:1 para um [RtcScreenShareQuality] real (sem células desabilitadas).
enum GoLiveQuality { auto, high, medium, low }

/// Mapeamento chip → perfil de publicação (captura fixa em 1080p60; o perfil é
/// o teto de transmissão, não a resolução de captura).
RtcScreenShareQuality goLiveQualityFor(GoLiveQuality quality) =>
    switch (quality) {
      GoLiveQuality.auto => RtcScreenShareQuality.auto,
      GoLiveQuality.high => RtcScreenShareQuality.q1080p60,
      GoLiveQuality.medium => RtcScreenShareQuality.q1080p30,
      GoLiveQuality.low => RtcScreenShareQuality.q720p15,
    };

/// Chip inicial a partir do perfil pendente. Órfãos (`q1080p15`, `q360p3`,
/// acessíveis só pelo sheet) caem no chip mais próximo.
GoLiveQuality goLiveQualityFromPending(RtcScreenShareQuality pending) =>
    switch (pending) {
      RtcScreenShareQuality.auto => GoLiveQuality.auto,
      RtcScreenShareQuality.q1080p60 => GoLiveQuality.high,
      RtcScreenShareQuality.q1080p30 ||
      RtcScreenShareQuality.q1080p15 => GoLiveQuality.medium,
      RtcScreenShareQuality.q720p15 ||
      RtcScreenShareQuality.q360p3 => GoLiveQuality.low,
    };

/// Escolha confirmada no modal Go Live: tipo/fonte resolvidos no seletor
/// (Windows: thumbnails; Linux: portal do sistema), qualidade one-shot e se
/// o áudio de sistema vai junto (opt-out, default ligado).
class GoLiveResult {
  const GoLiveResult({
    required this.kind,
    required this.sourceId,
    required this.quality,
    required this.includeAudio,
  });

  final RtcScreenShareSourceKind kind;
  final String? sourceId;
  final GoLiveQuality quality;
  final bool includeAudio;
}

/// Modal "Go Live" na língua do modal de configurações ([AppTokens] +
/// Geist): shell `surface2` com blur macOS, raio xl, `borderSubtle` e sombra
/// [AppShadows.modalWindow].
///
/// O modal configura só áudio + qualidade. O tipo/fonte é resolvido na etapa
/// seguinte: seletor com thumbnails no Windows, portal do sistema no Linux.
/// Fluxo: `Go Live` abre o seletor por cima do modal (stack, não replace) e
/// o chamador inicia com o retorno; cancelar em qualquer etapa retorna null
/// com o modal intacto. O modal nunca é fechado antes do seletor, então a
/// escolha one-shot não evapora.
Future<GoLiveResult?> showGoLiveModal(
  BuildContext context, {
  required NativeScreenShareBackend backend,
  required RtcScreenShareQuality pendingQuality,
  String? channelName,
}) {
  return showDialog<GoLiveResult>(
    context: context,
    builder: (context) => _GoLiveDialog(
      backend: backend,
      pendingQuality: pendingQuality,
      channelName: channelName,
    ),
  );
}

class _GoLiveDialog extends StatefulWidget {
  const _GoLiveDialog({
    required this.backend,
    required this.pendingQuality,
    required this.channelName,
  });

  final NativeScreenShareBackend backend;
  final RtcScreenShareQuality pendingQuality;
  final String? channelName;

  @override
  State<_GoLiveDialog> createState() => _GoLiveDialogState();
}

class _GoLiveDialogState extends State<_GoLiveDialog> {
  late GoLiveQuality _quality = goLiveQualityFromPending(widget.pendingQuality);

  /// Opt-out do áudio de sistema: ligado por padrão (regra 1 da SPEC).
  bool _includeAudio = true;

  bool get _canUseKind =>
      widget.backend.canUseKind(RtcScreenShareSourceKind.display) ||
      widget.backend.canUseKind(RtcScreenShareSourceKind.window);

  /// Aba inicial do seletor (Windows) / kind preservado no portal (Linux).
  RtcScreenShareSourceKind get _initialKind =>
      widget.backend.canUseKind(RtcScreenShareSourceKind.display)
      ? RtcScreenShareSourceKind.display
      : RtcScreenShareSourceKind.window;

  Future<void> _goLive() async {
    if (!_canUseKind) return;
    // Seletor abre POR CIMA do modal (stack, não replace): cancelar nele
    // volta para cá com a qualidade intacta. O tipo/fonte é resolvido no
    // seletor (Windows) ou no portal do sistema (Linux).
    final selection = await RtcScreenSharePicker.show(
      context,
      backend: widget.backend,
      initialKind: _initialKind,
    );
    if (!mounted || selection == null) return;
    Navigator.of(context).pop(
      GoLiveResult(
        kind: selection.kind,
        sourceId: selection.sourceId,
        quality: _quality,
        includeAudio: _includeAudio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channelName = widget.channelName;
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = (screenSize.width - 32).clamp(320.0, 460.0);
    final maxHeight = (screenSize.height - 32).clamp(320.0, 560.0);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTokens.surface2.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppTokens.borderSubtle, width: 1),
                  boxShadow: AppShadows.modalWindow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GoLiveTitleBar(onClose: () => Navigator.of(context).pop()),
                    Flexible(
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: SettingsStack(
                            maxWidth: 460,
                            children: [
                              if (channelName != null)
                                SettingsNotice(
                                  icon: Icons.tag_outlined,
                                  message:
                                      'Transmitindo no canal #$channelName',
                                ),
                              SettingsGroup(
                                title: 'Áudio da transmissão.',
                                children: [
                                  _AudioToggleRow(
                                    value: _includeAudio,
                                    onChanged: (value) =>
                                        setState(() => _includeAudio = value),
                                  ),
                                ],
                              ),
                              if (_includeAudio &&
                                  widget.backend.capabilities.usesSystemPicker)
                                const SettingsNotice(
                                  message:
                                      'Nesta plataforma o áudio compartilhado é o mix geral do sistema.',
                                ),
                              _QualityPanel(
                                quality: _quality,
                                onChanged: (quality) =>
                                    setState(() => _quality = quality),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _GoLiveActions(
                      canGoLive: _canUseKind,
                      onCancel: () => Navigator.of(context).pop(),
                      onGoLive: _goLive,
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

/// Titlebar igual ao modal de settings: título à esquerda, fechar à direita.
class _GoLiveTitleBar extends StatelessWidget {
  const _GoLiveTitleBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTokens.borderHairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Compartilhar tela',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppTokens.textPrimary,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          AppIconButton(
            icon: Icons.close,
            tooltip: 'Fechar (ESC)',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _GoLiveActions extends StatelessWidget {
  const _GoLiveActions({
    required this.canGoLive,
    required this.onCancel,
    required this.onGoLive,
  });

  final bool canGoLive;
  final VoidCallback onCancel;
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTokens.borderHairline, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancelar',
            variant: AppButtonVariant.ghost,
            onPressed: onCancel,
          ),
          const SizedBox(width: 8),
          AppButton(
            label: 'Go Live',
            icon: Icons.screen_share_outlined,
            onPressed: canGoLive ? onGoLive : null,
          ),
        ],
      ),
    );
  }
}

/// Toggle "Incluir áudio do sistema" (opt-out, default ligado): o áudio vai
/// junto com o share a menos que o usuário desligue.
class _AudioToggleRow extends StatelessWidget {
  const _AudioToggleRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTokens.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppTokens.borderHairline,
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.volume_up_outlined,
                    size: 15,
                    color: AppTokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Incluir áudio do sistema',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.textPrimary,
                          letterSpacing: 0,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Transmite todo o áudio do sistema.',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          height: 1.25,
                          color: AppTokens.textMuted,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SettingsSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Qualidades como radios compactos dentro do layout de settings.
class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.quality, required this.onChanged});

  final GoLiveQuality quality;
  final ValueChanged<GoLiveQuality> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = GoLiveQuality.values;
    return RadioGroup<GoLiveQuality>(
      groupValue: quality,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      child: SettingsGroup(
        title: 'Escolha a qualidade da transmissão.',
        children: [
          for (final value in values)
            _QualityRow(
              value: value,
              title: _qualityTitle(value),
              spec: _qualitySpec(value),
              selected: quality == value,
              onTap: () => onChanged(value),
            ),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.value,
    required this.title,
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final GoLiveQuality value;
  final String title;
  final String spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AppTokens.textPrimary
        : AppTokens.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: selected ? AppTokens.surface2 : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Radio<GoLiveQuality>(
                  value: value,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  splashRadius: 16,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppTokens.accentVercel;
                    }
                    if (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)) {
                      return AppTokens.textSecondary;
                    }
                    return AppTokens.textMuted;
                  }),
                  overlayColor: WidgetStateProperty.all(AppTokens.hoverOverlay),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: foreground,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: SettingsValueText(
                  spec,
                  color: selected
                      ? AppTokens.textSecondary
                      : AppTokens.textMuted,
                  monospace: true,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 16,
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: AppTokens.textPrimary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _qualityTitle(GoLiveQuality quality) => switch (quality) {
  GoLiveQuality.auto => 'Automática',
  GoLiveQuality.high => 'Alta',
  GoLiveQuality.medium => 'Média',
  GoLiveQuality.low => 'Baixa',
};

String _qualitySpec(GoLiveQuality quality) => switch (quality) {
  GoLiveQuality.auto => 'Sem downscale · até 15fps',
  GoLiveQuality.high => '1080p · até 60fps',
  GoLiveQuality.medium => '1080p · até 30fps',
  GoLiveQuality.low => '720p · 15fps',
};
